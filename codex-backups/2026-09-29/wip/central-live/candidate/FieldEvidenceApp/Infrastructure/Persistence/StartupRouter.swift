import Foundation
import SwiftData
import SwiftUI
import Darwin

/// Receipt-authenticated ownership observed by the existing startup writer.
/// These values alone never authorize a filesystem effect.
struct StartupMediaPhotoOwnershipV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let payload: CheckRunnerPhotoDraftPayloadV1
    let targetCommitted: Bool
}

struct StartupMediaOwnershipSnapshotV1: Equatable, Sendable {
    let revision: WorkspaceRevisionV1
    let authorities: [EvidenceBundleAuthority]
    let photos: [StartupMediaPhotoOwnershipV1]
}

@MainActor
final class StartupMediaRecoveryAuthorityV1 {
    let snapshot: StartupMediaOwnershipSnapshotV1
    private let validate: @MainActor () throws -> Void
    private var publishing = false

    fileprivate init(snapshot: StartupMediaOwnershipSnapshotV1,
                     validate: @escaping @MainActor () throws -> Void) {
        self.snapshot = snapshot; self.validate = validate
    }

    func validatePreparation() throws -> StartupMediaOwnershipSnapshotV1 {
        try validate()
        return snapshot
    }

    func revalidateCleanup(_ prepared: StartupMediaPreparedRecoveryV1) throws {
        guard publishing, prepared.snapshot == snapshot else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }
        try validate()
    }

    /// Issued only inside the original access and generation publication holds.
    fileprivate func publish(_ prepared: StartupMediaPreparedRecoveryV1) throws {
        guard !publishing else { throw EvidenceBundleStoreError.bundleFactsMismatch }
        publishing = true
        defer { publishing = false }
        try prepared.finish(authority: self)
    }
}

/// Only the router can mint this capability for its unpublished startup writer.
@MainActor
final class StartupPrivatePreparationAuthorityV1 {
    let generationRootURL: URL
    let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let validate: @MainActor () throws -> Void
    private var publishing = false

    fileprivate init(generationRootURL: URL, rootIdentity: ReportPDFAnchoredFile.RootIdentity,
        validate: @escaping @MainActor () throws -> Void) {
        self.generationRootURL = generationRootURL; self.rootIdentity = rootIdentity; self.validate = validate
    }

    func validatePreparation() throws -> (root: URL, identity: ReportPDFAnchoredFile.RootIdentity) {
        try validate()
        return (generationRootURL, rootIdentity)
    }

    func revalidateCleanup() throws {
        guard publishing else { throw StartupMaintenanceReason.finalizationInconsistent }
        try validate()
    }

    fileprivate func publish(_ prepared: FinalizationIntentStore.StartupPrivateRetirement) throws {
        guard !publishing else { throw StartupMaintenanceReason.finalizationInconsistent }
        publishing = true
        defer { publishing = false }
        try prepared.finish(authority: self)
    }
}

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
#if DEBUG
enum StartupRuntimeObservationPhaseV1: String, Equatable, Sendable {
    case preflight
    case erase
    case restore
    case currentOpen
    case fieldDraft
    case finalization
    case deletion
    case media
    case pdf
    case sourceHistory
    case diagnostics
    case commerce
    case ready
}

struct StartupRuntimeObservationV1: Equatable, Sendable {
    let phase: StartupRuntimeObservationPhaseV1
    let startedAtUptimeNanoseconds: UInt64
    var endedAtUptimeNanoseconds: UInt64?
}
#endif

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
        case eraseCleanupPending(ErasePendingRoute)

        case maintenance(StartupMaintenanceReason)
    }

    @Published private(set) var route: Route = .checking
#if DEBUG
    private(set) var runtimeObservation: StartupRuntimeObservationV1?
    /// Fixed phase/type observations only; silent by default.
    var startupFailureDiagnosticForTesting: (@MainActor (String) -> Void)?
    var originalOpenFixedDiagnosticsForTesting: Bool {
        get { generationFactory.coldOpenFixedDiagnosticsForTesting }
        set { generationFactory.coldOpenFixedDiagnosticsForTesting = newValue }
    }
    private var currentOpenBoundaryForTesting = "unobserved"

    private func reportStartupFailureForTesting(_ error: Error) {
        guard let observe = startupFailureDiagnosticForTesting else { return }
        let phase = runtimeObservation?.phase.rawValue ?? "unobserved"
        let errorType = String(reflecting: type(of: error))
        let policyMismatch = (error as? ProtectedFilePolicyError) == .resourceValueMismatch
        observe("phase=\(phase) type=\(errorType) resourceValueMismatch=\(policyMismatch) currentOpenBoundary=\(currentOpenBoundaryForTesting)")
    }
#endif
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
    enum ErasePendingRoute {
        case preparing(StoreSessionCoordinator)
        case retiring(EraseRouterOperationV1)
    }

    private var generationFactory: StoreGenerationFactory
    private let diagnosticsStore: DiagnosticsStore
    private let fileManager: FileManager
    private let entitlementRuntime: StoreKitEntitlementRuntimeV1
    private let didBeginStep: (StartupStep) -> Void
    private let beforePostAdoptionContentRead: @MainActor (UUID) async -> Void
    private let willReadPostAdoptionCanonicalContent: @MainActor (UUID) -> Void
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
    /// A router-owned capability for an already admitted external operation.
    /// It deliberately has no serializable identity: a callback can continue
    /// only the operation which minted this exact value.
    struct OriginalOperationTicket: Sendable {
        fileprivate let owner: OriginalOperationOwner
        fileprivate let mint: OriginalOperationMint
        fileprivate let operationID: UUID
    }
    fileprivate final class OriginalOperationOwner: @unchecked Sendable {}
    fileprivate final class OriginalOperationMint: @unchecked Sendable {
        // Metadata only; owner/mint reference identity remains authority.
        let eraseBindingID = UUID()
    }
    private enum OriginalOperationKind: Equatable { case restore, erase }
    /// Tickets must never keep an old SwiftData context alive: Erase drain is
    /// precisely the proof that the old context has gone away.
    private final class OriginalOperationSourceReference {
        weak var coordinator: StoreSessionCoordinator?
        weak var modelContext: ModelContext?

        init(coordinator: StoreSessionCoordinator?, modelContext: ModelContext) {
            self.coordinator = coordinator
            self.modelContext = modelContext
        }
    }
    private struct OriginalOperationState {
        let kind: OriginalOperationKind
        let owner: OriginalOperationOwner
        let mint: OriginalOperationMint
        let sourceGenerationID: UUID
        let source: OriginalOperationSourceReference
        let authorization: StartupAuthorization
        // Held only before admission is issued. Release before any Erase
        // construction so this recovery service cannot keep source models alive.
        var eraseReturnStartup: PreparedStartup?
        var eraseSubject: EraseAllOperationSubjectV1?
        var eraseAuthorizationIssued = false
        var acknowledgedReservation: AppAccessGateV1.EraseAdoptionToken?
        var postAdoptionStartup = false
        var postAdoptionExecutionID: UUID?
        var restoreSourceExit: RestoreSourceReaderExitV1?
        var restoreDrainID: UUID?
        var restoreSourceWriterHandle: GenerationLeaseHandleV1?
        var restoreTargetPointerData: Data?
    }
    private let originalOperationOwner = OriginalOperationOwner()
    private var originalOperations: [UUID: OriginalOperationState] = [:]
    private final class PendingRestoreReaderTransition {
        enum Phase: Equatable { case waitingForOldAliases, sourceClosed, rebound, recovering, uncertain }
        let id: UUID
        let ticket: OriginalOperationTicket
        let source: RestoreSourceReaderExitV1
        let targetSession: StoreGenerationSession
        let targetFactory: StoreGenerationFactory
        let targetReader: GenerationLeaseHandleV1
        let writerOwner: RestoreWriterTransitionOwnerV1
        let targetCoordinator: StoreSessionCoordinator
        let targetWriter: GenerationLeaseHandleV1
        let originalFactory: StoreGenerationFactory
        var phase = Phase.waitingForOldAliases

        init(ticket: OriginalOperationTicket,
             source: RestoreSourceReaderExitV1,
             targetSession: StoreGenerationSession,
             targetFactory: StoreGenerationFactory,
             targetReader: GenerationLeaseHandleV1,
             writerOwner: RestoreWriterTransitionOwnerV1,
             targetCoordinator: StoreSessionCoordinator,
             targetWriter: GenerationLeaseHandleV1,
             originalFactory: StoreGenerationFactory) {
            id = UUID()
            self.ticket = ticket
            self.source = source
            self.targetSession = targetSession
            self.targetFactory = targetFactory
            self.targetReader = targetReader
            self.writerOwner = writerOwner
            self.targetCoordinator = targetCoordinator
            self.targetWriter = targetWriter
            self.originalFactory = originalFactory
        }
    }
    private var pendingRestoreReaderTransition: PendingRestoreReaderTransition?
    private var retainedRestoreOldCoordinatorOnFailure: StoreSessionCoordinator?
    private var retainedRestoreTargetSessionOnFailure: StoreGenerationSession?
    private var retainedRestoreWriterAttemptOnFailure: RestoreWriterTransitionOwnerV1?
    private var maintenanceClearObservation: RestoreMaintenanceClearObservationV1?
    private static var retainedUncertainMaintenanceObservations:
        [RestoreMaintenanceClearObservationV1] = []
    private var maintenanceControlFrame: RestoreMaintenanceClearObservationV1.Frame?
    private var maintenanceOperationsExpectedFrame: RestoreMaintenanceClearObservationV1.Frame?
    private var maintenanceOperationsOwner: RestoreMaintenanceClearObservationV1?
    private var maintenanceFinalizationStore: FinalizationIntentStore?
    private var maintenanceFinalizationDescriptorOwner:
        RestoreMaintenanceOperationsDescriptorOwnerV1?
    private var maintenanceDeletionService: WholeSignDeletionService?
    private var maintenanceDeletionDescriptorOwner:
        RestoreMaintenanceOperationsDescriptorOwnerV1?
    private var maintenanceOperationsUncertain = false
    private weak var maintenanceFrameSession: StoreGenerationSession?
    private weak var maintenanceFrameReader: GenerationLeaseHandleV1?
    private var maintenanceFrameOpeningFactory: StoreGenerationFactory?
    private var maintenanceFrameHadInstalledWriter = false
    private var coldErasePreparation: EraseColdPreparationOperationV1?
    private var coldEraseRetirement: EraseColdRetirementAuthorityV1?
    private var retainedEraseRetirementOperation: EraseRouterOperationV1?
#if DEBUG
    private var abandonedOriginalEraseForColdRestart = false
    // The original registry guard and any uncertain release attempts remain
    // alive even if the test replaces every ordinary Router reference.
    private static var retainedOriginalEraseShutdownOwnersForTesting: [EraseRouterOperationV1] = []
    private static var retainedPostRetiredOriginalServicesForTesting: [EraseAllService] = []
    private static var retainedPreactivationDurableShutdownsForTesting:
        [(router: StartupRouter, service: EraseAllService)] = []
    private var notificationRefusalColdExitForTesting: (
        operation: EraseRouterOperationV1,
        service: EraseAllService,
        subject: EraseAllOperationSubjectV1
    )?
    private struct CompletedAbortShutdown {
        let operation: EraseRouterOperationV1
        let service: EraseAllService
        let receipt: AbortedEraseAdmissionReceiptV1
        let coordinator: StoreSessionCoordinator
        var drainID: UUID?
        var lifecycleReleased = false
    }
    private var completedAbortShutdown: CompletedAbortShutdown?
    private var completedAbortFinal: (
        operation: EraseRouterOperationV1,
        service: EraseAllService,
        receipt: AbortedEraseAdmissionReceiptV1
    )?
    private var completedAbortPreAliasSealed = false
#endif
    private var detachedEraseRetirement: EraseSessionRetirementV1?
    private var freshEraseAdoption: EraseFreshAdoptionOwnerV1?
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
#if DEBUG
    /// Test observation after read-only preparation, before final authorization.
    var beforeCurrentMediaCleanupForTesting: (@MainActor (ModelContext) async throws -> Void)?
    var beforePrivatePreparationCleanupForTesting: (@MainActor (ModelContext) async throws -> Void)?
    /// Runs only after ordinary startup writer cleanup has settled and just
    /// before maintenance eligibility reads the existing Restore controls.
    var beforeMaintenanceClearObservationForTesting: (@MainActor () throws -> Void)?
#endif
    fileprivate enum StartupAuthorization {
        case content(AppAccessGateV1, AppAccessGateV1.ContentReadToken)
        case configuration(NotificationOperationAuthorizationV1)

        var permitsPublication: Bool {
            if case .content = self { return true }
            return false
        }

        func validate() async throws {
            switch self {
            case .content(let gate, let token):
                try await gate.validateContentRead(token, for: .startupRecovery)
            case .configuration(let authorization):
                try await authorization.validateStartupRecovery()
            }
        }

        func withMediaRecovery<T>(_ body: () throws -> T) throws -> T {
            switch self {
            case .content(_, let token):
                return try token.withContentRead(for: .startupRecovery, body)
            case .configuration(let authorization):
                guard let token = authorization.startupRecoveryToken else {
                    throw AppAccessContractFailureV1.accessDenied
                }
                return try token.withStartupRecovery(operationID: authorization.operationID, body)
            }
        }
    }
    private struct PostAdoptionExecution {
        let ticket: OriginalOperationTicket
        let executionID: UUID
        let contentReadToken: AppAccessGateV1.ContentReadToken
    }
    private struct PreparedStartup {
        let owner: OwnedWriter
        let recovery: ReportRecoveryService
        // Present only after the exact unadmitted original Erase returned.
        // Other prepared startup routes cannot reopen Whole Sign deletion.
        let unadmittedEraseCaptureOperationID: UUID?

        init(owner: OwnedWriter, recovery: ReportRecoveryService,
             unadmittedEraseCaptureOperationID: UUID? = nil) {
            self.owner = owner
            self.recovery = recovery
            self.unadmittedEraseCaptureOperationID = unadmittedEraseCaptureOperationID
        }
    }
    private var startupAccessGate: AppAccessGateV1?
    private var operationAuthorization: StartupAuthorization?
    private var temporalNormalizationOperation: TemporalNormalizationOperationAuthorityV1?
    private var temporalColdOperation: TemporalNormalizationColdOperationAuthorityV1?
    private var preparedStartup: PreparedStartup?
    private(set) var lastStartupAccessFailure: Error?
    private var pendingEraseDrainProof: EraseGenerationDrainProof?
    // Deferred cleanup still has a live-process drain obligation. Keep its
    // non-content route owner independently of the writer retired on locking.
    private var deferredEraseCoordinator: StoreSessionCoordinator?
    private var pendingErasedActivation: (owner: OwnedWriter, session: StoreGenerationSession, operationID: UUID)?
    /// Exact pre-cleanup ownership survives invalidation and a failed close.
    /// It never authorizes reads through the retired writer or another binding.
    private struct EraseCleanupRetirement {
        let owner: OwnedWriter
        let session: StoreGenerationSession
        let operationID: UUID
        var released = false
    }
    private var eraseCleanupRetirement: EraseCleanupRetirement?
    private var retainsGenerationsUntilColdLaunch = false
    private var pendingWriterLeaseReleases: [StoreSessionWriterCleanupFailureV1] = []
    private var pendingCoordinatorReleases: [OwnedWriter] = []
    /// A no-effect Erase abort may return while the original SwiftData reader
    /// is still live.  Keep its actual inventory until checked writer release
    /// and weak original-alias drain permit reader close before another open.
    private struct PendingAbortedOriginalReaderRetirement {
        let operation: EraseRouterOperationV1
        let receipt: AbortedEraseAdmissionReceiptV1
    }
    private var pendingAbortedOriginalReaderRetirements: [PendingAbortedOriginalReaderRetirement] = []
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

    /// The original presentation token fences both live store identity and
    /// reconciliation. Call the pure coordinator inside this one hold; nesting
    /// another token hold would reacquire the same nonrecursive lock.
    func restoreSceneNavigationState(
        _ request: RouteRestorationRequestV1,
        using coordinator: RouteCoordinatorV1,
        workspaceID: WorkspaceID,
        generationID: UUID,
        authorization: AppAccessGateV1.ContentReadToken
    ) throws -> SceneNavigationRestorationResultV1 {
        guard startupAccessGate?.issuedContentReadToken(authorization) == true else {
            throw AppAccessContractFailureV1.accessDenied
        }
        return try authorization.withContentRead(for: .sceneRestoration) {
            guard case .ready(let store, _, _) = route,
                  store.workspaceID == workspaceID,
                  store.generationID == generationID,
                  request.context.currentWorkspaceID == workspaceID else {
                throw AppAccessContractFailureV1.accessDenied
            }
            let revision = try store.workspaceWriter.currentRevision()
            guard request.context.currentRevision == revision.revision else {
                throw WorkspaceMutationFailureV1.staleWorkspaceRevision
            }
            return try restoreSceneFromCanonicalSource(request, using: coordinator, store: store)
        }
    }

    /// UI supplies navigation values only. Workspace revision and target
    /// availability are read from the current canonical owner in the same hold.
    func restoreSceneNavigationState(
        loaded: SceneNavigationLoadResultV1,
        explicitIngressTarget: NavigationTargetV1?,
        using coordinator: RouteCoordinatorV1,
        workspaceID: WorkspaceID,
        generationID: UUID,
        authorization: AppAccessGateV1.ContentReadToken,
        evidenceKind: RouteEvidenceKindV1,
        receiptID: UUID
    ) throws -> SceneNavigationRestorationResultV1 {
        guard startupAccessGate?.issuedContentReadToken(authorization) == true else {
            throw AppAccessContractFailureV1.accessDenied
        }
        return try authorization.withContentRead(for: .sceneRestoration) {
            guard case .ready(let store, _, _) = route,
                  store.workspaceID == workspaceID,
                  store.generationID == generationID else {
                throw AppAccessContractFailureV1.accessDenied
            }
            let snapshot: SceneNavigationSnapshotV1?
            let discardReason: RouteFallbackReasonV1?
            switch loaded {
            case .absent: snapshot = nil; discardReason = nil
            case .restored(let value): snapshot = value; discardReason = nil
            case .discarded(let reason): snapshot = nil; discardReason = reason
            }
            let revision = try store.workspaceWriter.currentRevision()
            let request = RouteRestorationRequestV1(
                context: .init(currentWorkspaceID: workspaceID, currentRevision: revision.revision),
                startupMaintenanceTarget: nil, incompleteMutationRecoveryTarget: nil,
                explicitIngressTarget: explicitIngressTarget, sceneSnapshot: snapshot,
                discardedSnapshotReason: discardReason, evidenceKind: evidenceKind, receiptID: receiptID)
            return try restoreSceneFromCanonicalSource(request, using: coordinator, store: store)
        }
    }

    /// Caller owns the single scene token hold. Invalid snapshots retain the
    /// coordinator's discard behavior and cannot expand canonical lookups.
    private func restoreSceneFromCanonicalSource(
        _ request: RouteRestorationRequestV1,
        using coordinator: RouteCoordinatorV1,
        store: StoreSessionCoordinator
    ) throws -> SceneNavigationRestorationResultV1 {
        var targets = [request.startupMaintenanceTarget,
                       request.incompleteMutationRecoveryTarget,
                       request.explicitIngressTarget].compactMap { $0 }
        if let snapshot = request.sceneSnapshot,
           snapshot.workspaceID == store.workspaceID,
           (try? snapshot.validate()) != nil {
            targets.append(contentsOf: snapshot.paths.flatMap(\.targets))
        }
        let context = try ProductionSceneNavigationSourceV1.context(
            for: targets, in: store, registry: coordinator.registry)
        let canonicalRequest = RouteRestorationRequestV1(
            context: context, startupMaintenanceTarget: request.startupMaintenanceTarget,
            incompleteMutationRecoveryTarget: request.incompleteMutationRecoveryTarget,
            explicitIngressTarget: request.explicitIngressTarget, sceneSnapshot: request.sceneSnapshot,
            discardedSnapshotReason: request.discardedSnapshotReason,
            evidenceKind: request.evidenceKind, receiptID: request.receiptID)
        return try coordinator.restoreScene(canonicalRequest)
    }

    func retryChecks(accessGate: any AppAccessGatePortV1) async throws {
        guard pendingRestoreReaderTransition == nil else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        let authorization = try await startupAuthorization(accessGate)
        await runStartup(authorization: authorization)
        try await authorization.validate()
        if let lastStartupAccessFailure { throw lastStartupAccessFailure }
    }

    /// The sole startup operation allowed before an app-access permit. The
    /// injected ingress store guarantees metadata-only cleanup and fails
    /// closed on uncertain ownership; this method never opens a store.
    func performPreAuthenticationScratchHygiene(
        ingressStore: any ProtectedIngressStoreV1,
        now: Date,
        operationID: UUID
    ) async throws -> ProtectedIngressStartupHygieneReceiptV1 {
#if DEBUG
        guard !abandonedOriginalEraseForColdRestart else {
            throw AppAccessContractFailureV1.staleAttempt
        }
#endif
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
        beforePostAdoptionContentRead: @escaping @MainActor (UUID) async -> Void = { _ in },
        willReadPostAdoptionCanonicalContent: @escaping @MainActor (UUID) -> Void = { _ in },
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
        self.beforePostAdoptionContentRead = beforePostAdoptionContentRead
        self.willReadPostAdoptionCanonicalContent = willReadPostAdoptionCanonicalContent
        self.beforeCommerceActivation = beforeCommerceActivation
    }

    func startIfNeeded() async {
        guard pendingRestoreReaderTransition == nil else { return }
#if DEBUG
        if abandonedOriginalEraseForColdRestart { return }
#endif
        if let startupAccessGate {
            do { try await startIfNeeded(accessGate: startupAccessGate) }
            catch { lastStartupAccessFailure = error }
            return
        }
        guard !hasStarted else {
            return
        }

        hasStarted = true
        await retryChecks()
    }

    func startIfNeeded(accessGate: any AppAccessGatePortV1) async throws {
        guard pendingRestoreReaderTransition == nil else {
            throw AppAccessContractFailureV1.invalidTransition
        }
#if DEBUG
        guard !abandonedOriginalEraseForColdRestart else {
            throw AppAccessContractFailureV1.staleAttempt
        }
#endif
        let authorization = try await startupAuthorization(accessGate)
        if let preparedStartup {
            try await publishPreparedStartup(preparedStartup, authorization: authorization)
            hasStarted = true
            return
        }
        guard !hasStarted else { return }
        hasStarted = true
        await runStartup(authorization: authorization)
        try await authorization.validate()
        if let lastStartupAccessFailure { throw lastStartupAccessFailure }
    }

    func retryChecks() async {
        guard pendingRestoreReaderTransition == nil else { return }
        if let startupAccessGate {
            do { try await retryChecks(accessGate: startupAccessGate) }
            catch { lastStartupAccessFailure = error }
            return
        }
        await runStartup(authorization: nil)
    }

    func bindStartupAccessGate(_ gate: AppAccessGateV1) throws {
#if DEBUG
        guard !abandonedOriginalEraseForColdRestart else {
            throw AppAccessContractFailureV1.staleAttempt
        }
#endif
        if let startupAccessGate {
            guard startupAccessGate === gate else { throw AppAccessContractFailureV1.accessDenied }
        } else {
            guard !hasStarted, !isRunning, publishedWriter == nil, preparedStartup == nil else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            startupAccessGate = gate
        }
    }

    /// Admit Restore before the service can inspect or mutate an original
    /// generation.  The ticket retains the concrete content-read epoch; a
    /// later unlock must never substitute a new permit for this operation.
    func beginRestoreOperation(
        sourceModelContext: ModelContext,
        sourceGenerationID: UUID,
        coordinator: StoreSessionCoordinator?,
        validatedPackage: ValidatedV4BackupPackageV1,
        accessGate: AppAccessGateV1
    ) async throws -> OriginalOperationTicket {
        guard pendingRestoreReaderTransition == nil,
              pendingEraseDrainProof == nil, !isRunning,
              pendingAbortedOriginalReaderRetirements.isEmpty,
              originalOperations.isEmpty else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        let authorization = try await startupAuthorization(accessGate)
        guard pendingRestoreReaderTransition == nil,
              pendingEraseDrainProof == nil, !isRunning,
              pendingAbortedOriginalReaderRetirements.isEmpty,
              originalOperations.isEmpty else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let sourceSession: StoreGenerationSession
        let sourceWriter: WorkspaceWriterV1?
        let sourceWriterHandle: GenerationLeaseHandleV1?
        if let coordinator {
            let captured = try coordinator.requireOriginalRestoreSource(
                context: sourceModelContext,
                generationID: sourceGenerationID,
                factory: generationFactory)
            sourceSession = captured.session
            sourceWriter = captured.writer
            sourceWriterHandle = captured.writerHandle
            guard case let .ready(published, _, _) = route,
                  published === coordinator,
                  publishedWriter?.coordinator === coordinator,
                  publishedWriter?.writer === captured.writer else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        } else {
            guard let maintenanceRestoreSession,
                  maintenanceRestoreSession.modelContext === sourceModelContext,
                  maintenanceRestoreSession.generationID == sourceGenerationID,
                  case .maintenance = route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            sourceSession = maintenanceRestoreSession
            sourceWriter = nil
            sourceWriterHandle = nil
            try requireMaintenanceFrame(sourceSession,
                validatedImport: validatedPackage)
        }
        // This retention is an admission property, not a post-service
        // cleanup detail.  It therefore survives every suspended callback.
        retainsGenerationsUntilColdLaunch = true
        let sourceExit = try RestoreSourceReaderExitV1(
            session: sourceSession, sourceContext: sourceModelContext,
            coordinator: coordinator, factory: generationFactory)
        let operation = beginOperation(.restored, authorization: authorization)
        let mint = OriginalOperationMint()
        originalOperations[operation] = OriginalOperationState(
            kind: .restore, owner: originalOperationOwner, mint: mint,
            sourceGenerationID: sourceGenerationID,
            source: OriginalOperationSourceReference(
                coordinator: coordinator, modelContext: sourceModelContext
            ), authorization: authorization, restoreSourceExit: sourceExit,
            restoreSourceWriterHandle: sourceWriterHandle
        )
        do {
            if let coordinator, let sourceWriter {
                let drainID = try coordinator.beginOriginalRestoreProducerDrain(
                    source: sourceSession, expectedWriter: sourceWriter)
                originalOperations[operation]?.restoreDrainID = drainID
                try await coordinator.awaitOriginalRestoreProducerDrain(drainID)
                guard operationID == operation,
                      originalOperations[operation]?.mint === mint,
                      coordinator.modelContext === sourceModelContext,
                      coordinator.workspaceWriter === sourceWriter else {
                    throw AppAccessContractFailureV1.staleAttempt
                }
            }
            try await authorization.validate()
            guard operationID == operation,
                  originalOperations[operation]?.mint === mint else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            if coordinator == nil {
                try requireMaintenanceFrame(sourceSession,
                    validatedImport: validatedPackage)
            }
            try sourceExit.capturePhysical()
        } catch {
            // The exact source controls remain attached to originalOperations;
            // a failed checked observation cannot become a new baseline.
            route = .maintenance(.restoreInconsistent)
            throw error
        }
        return OriginalOperationTicket(owner: originalOperationOwner, mint: mint,
                                       operationID: operation)
    }

    func validateRestoreOperation(_ ticket: OriginalOperationTicket) async throws {
        let state = try await validateOriginalOperation(ticket, kind: .restore)
        try await state.authorization.validate()
    }

    /// The original Restore service calls this only after publishing and
    /// checking its pre-switch intended pointer. It does not acknowledge a
    /// completed Restore: activation still requires the returned B session.
    func attestRestorePublishedPointer(originalCanonicalPointer: Data,
        targetCanonicalPointer: Data,
        ticket: OriginalOperationTicket) throws {
        guard ticket.owner === originalOperationOwner,
              operationID == ticket.operationID,
              operationKind == .restored,
              let state = originalOperations[ticket.operationID],
              state.kind == .restore, state.mint === ticket.mint,
              let source = state.restoreSourceExit,
              state.restoreTargetPointerData == nil,
              case .v3(let pointer, _) = try CurrentPointerCodecV1.decode(
                  targetCanonicalPointer),
              try pointer.canonicalData() == targetCanonicalPointer,
              pointer.generationID != state.sourceGenerationID.uuidString.lowercased() else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try source.requireOriginalPointerAttestation(originalCanonicalPointer)
        originalOperations[ticket.operationID]?.restoreTargetPointerData
            = targetCanonicalPointer
    }

    /// Admission is intentionally separate from the service subject.  The
    /// service mints that subject immediately before its first effect; root
    /// passes this original token to the lifecycle exactly once at that edge.
    func beginEraseOperation(
        coordinator: StoreSessionCoordinator,
        accessGate: AppAccessGateV1
    ) async throws -> OriginalOperationTicket {
        guard !isRunning, pendingRestoreReaderTransition == nil,
              pendingEraseDrainProof == nil,
              pendingAbortedOriginalReaderRetirements.isEmpty,
              originalOperations.isEmpty, resolvePendingWriterCleanup(),
              publishedWriter.map({ $0.coordinator === coordinator &&
                  $0.writer === coordinator.workspaceWriter }) ?? true else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        try requireOriginalEraseSourceOwner(coordinator)
        if case .maintenance = route {
            let source = try coordinator.requireOriginalEraseOpeningAuthority(
                factory: generationFactory)
            try requireMaintenanceFrame(source)
        }
        let authorization = try await startupAuthorization(accessGate)
        guard !isRunning, pendingRestoreReaderTransition == nil,
              pendingEraseDrainProof == nil,
              pendingAbortedOriginalReaderRetirements.isEmpty,
              originalOperations.isEmpty, resolvePendingWriterCleanup(),
              publishedWriter.map({ $0.coordinator === coordinator &&
                  $0.writer === coordinator.workspaceWriter }) ?? true else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        // Authentication suspends. Reprove the exact session, source reader
        // and writer provider before inventory capture or any route mutation.
        try requireOriginalEraseSourceOwner(coordinator)
        if case .maintenance = route {
            let source = try coordinator.requireOriginalEraseOpeningAuthority(
                factory: generationFactory)
            try requireMaintenanceFrame(source)
        }
        let returnStartup: PreparedStartup?
        if let publishedWriter, case let .ready(actual, _, recovery) = route,
           actual === coordinator, publishedWriter.coordinator === coordinator {
            returnStartup = PreparedStartup(owner: publishedWriter, recovery: recovery)
        } else {
            returnStartup = nil
        }
        let inventory = EraseReaderRetirementInventoryV1()
        try coordinator.captureEraseSession(in: inventory)
        let operation = beginOperation(.erase, authorization: authorization)
        operationOwnedWriter = publishedWriter
        publishedWriter = nil
        pendingEraseDrainProof = EraseGenerationDrainProof(
            priorContext: coordinator.modelContext
        )
        let mint = OriginalOperationMint()
        var eraseState = OriginalOperationState(
            kind: .erase, owner: originalOperationOwner, mint: mint,
            sourceGenerationID: coordinator.generationID,
            source: OriginalOperationSourceReference(
                coordinator: coordinator, modelContext: coordinator.modelContext
            ), authorization: authorization
        )
        eraseState.eraseReturnStartup = returnStartup
        originalOperations[operation] = eraseState
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        let ticket = OriginalOperationTicket(owner: originalOperationOwner, mint: mint, operationID: operation)
        let retirementOperation = EraseRouterOperationV1(router: self, ticket: ticket, inventory: inventory)
        retainedEraseRetirementOperation = retirementOperation
        try inventory.bindPreparation(operation: retirementOperation)
        try coordinator.captureErasePreparationSource(operation: retirementOperation)
        return ticket
    }

    /// Returns the original permit once.  It does not reserve at the gate:
    /// the lifecycle owns that atomic reservation and exact-subject resume.
    private func requireOriginalEraseSourceOwner(
        _ coordinator: StoreSessionCoordinator
    ) throws {
        let session = try coordinator.requireOriginalEraseOpeningAuthority(
            factory: generationFactory)
        switch route {
        case .ready(let actual, _, _):
            guard let publishedWriter,
                  actual === coordinator,
                  publishedWriter.coordinator === coordinator,
                  publishedWriter.writer === coordinator.workspaceWriter else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        case .maintenance:
            guard maintenanceEraseSession === session,
                  publishedWriter == nil else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        default:
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    /// Returns the original permit once.  It does not reserve at the gate:
    /// the lifecycle owns that atomic reservation and exact-subject resume.
    func eraseAdmissionAuthorization(
        _ ticket: OriginalOperationTicket,
        subject: EraseAllOperationSubjectV1
    ) async throws -> AppAccessGateV1.ContentReadToken? {
        var state = try await validateOriginalOperation(ticket, kind: .erase)
        guard temporalNormalizationOperation == nil, temporalColdOperation == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        if let bound = state.eraseSubject {
            guard bound == subject else { throw AppAccessContractFailureV1.staleAttempt }
            // The lifecycle reservation legitimately revoked the original
            // read token.  Exact-subject recovery continues under that
            // retained reservation and must not mint a replacement permit.
            return nil
        }
        try await state.authorization.validate()
        guard case let .content(_, token) = state.authorization else {
            throw AppAccessContractFailureV1.accessDenied
        }
        temporalNormalizationOperation?.revoke()
        temporalNormalizationOperation = nil
        temporalColdOperation?.revoke()
        temporalColdOperation = nil
        // Admission consumes the no-effect return path before any service
        // effect. Do not retain its context-bearing recovery service in Erase.
        state.eraseReturnStartup = nil
        state.eraseSubject = subject
        state.eraseAuthorizationIssued = true
        originalOperations[ticket.operationID] = state
        return token
    }

    /// The lifecycle, not the router, owns gate reservation.  Once it has
    /// atomically accepted the original token, bind that exact reservation so
    /// a later failure cannot pretend the pre-effect admission was absent.
    func recordEraseReservation(
        _ ticket: OriginalOperationTicket,
        reservation: AppAccessGateV1.EraseAdoptionToken
    ) throws {
        guard ticket.owner === originalOperationOwner,
              var state = originalOperations[ticket.operationID],
              state.owner === ticket.owner, state.mint === ticket.mint,
              state.kind == .erase, operationID == ticket.operationID,
              state.eraseSubject == reservation.subject,
              state.acknowledgedReservation == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        state.acknowledgedReservation = reservation
        originalOperations[ticket.operationID] = state
    }

    private func validateOriginalOperation(
        _ ticket: OriginalOperationTicket,
        kind: OriginalOperationKind
    ) async throws -> OriginalOperationState {
        let matchesOperationKind: Bool
        switch (kind, operationKind) {
        case (.restore, .restored), (.erase, .erase): matchesOperationKind = true
        default: matchesOperationKind = false
        }
        guard ticket.owner === originalOperationOwner,
              let state = originalOperations[ticket.operationID],
              state.owner === ticket.owner, state.mint === ticket.mint,
              state.kind == kind, operationID == ticket.operationID,
              matchesOperationKind, isRunning else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return state
    }

    private func removeOriginalOperation(_ operation: UUID) {
        if retainedEraseRetirementOperation?.ticket.operationID == operation,
           originalOperations[operation]?.acknowledgedReservation != nil {
            // Only actual abort or completed publication clears this owner.
            // Generic invalidation must not discard leased cleanup resources.
            return
        }
        if retainedEraseRetirementOperation?.ticket.operationID == operation {
            retainedEraseRetirementOperation = nil
        }
        originalOperations.removeValue(forKey: operation)
        if eraseCleanupRetirement?.operationID == operation {
            eraseCleanupRetirement = nil
        }
    }

    /// A stale or foreign completion cannot tear down the operation which
    /// replaced it.  Only the exact current ticket may close this route.
    func failExternalOperation(_ ticket: OriginalOperationTicket) {
        if pendingRestoreReaderTransition?.ticket.operationID == ticket.operationID { return }
        guard ticket.owner === originalOperationOwner,
              let state = originalOperations[ticket.operationID],
              state.mint === ticket.mint,
              operationID == ticket.operationID || operationID == nil else { return }
        if let value = retainedEraseRetirementOperation {
            do { try value.requireNoRetirementResourcesForAbort() }
            catch { invalidateOperationAndPublishedWriter(); return }
        }
        if state.kind == .restore, state.restoreSourceExit != nil {
            // The service may already have published B. Retain the exact A
            // controls and ticket instead of generic startup invalidation.
            route = .maintenance(.restoreInconsistent)
            return
        }
        removeOriginalOperation(ticket.operationID)
        if state.kind == .erase {
            // No service subject means no physical effect and no lifecycle
            // reservation.  Release the pre-effect drain hold rather than
            // stranding a weak old-context obligation on cancellation.
            if state.acknowledgedReservation == nil {
                pendingEraseDrainProof = nil
                deferredEraseCoordinator = nil
            }
            failClosedErase()
        }
        else {
            invalidateOperationAndPublishedWriter()
            route = .maintenance(.restoreInconsistent)
        }
    }

    /// Return the existing writer only when Erase never issued admission
    /// authority. This is not an abort receipt or permission to publish content.
    func cancelUnadmittedErase(_ ticket: OriginalOperationTicket) throws {
        guard ticket.owner === originalOperationOwner,
              let state = originalOperations[ticket.operationID],
              state.owner === ticket.owner, state.mint === ticket.mint,
              state.kind == .erase, state.eraseSubject == nil,
              !state.eraseAuthorizationIssued, state.acknowledgedReservation == nil,
              operationID == ticket.operationID, operationKind == .erase, isRunning,
              let retirement = retainedEraseRetirementOperation,
              retirement.ticket.mint === ticket.mint,
              let owner = operationOwnedWriter, publishedWriter == nil,
              preparedStartup == nil, let returnStartup = state.eraseReturnStartup,
              returnStartup.owner.coordinator === owner.coordinator,
              returnStartup.owner.writer === owner.writer,
              returnStartup.owner.generationID == owner.generationID,
              state.source.coordinator === owner.coordinator,
              state.source.modelContext === owner.coordinator.modelContext,
              state.sourceGenerationID == owner.generationID,
              pendingErasedActivation == nil, detachedEraseRetirement == nil,
              freshEraseAdoption == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        // The original epoch must still be valid for these reads. A revoked
        // epoch or uncertain allocation retains the operation for recovery.
        try state.authorization.withMediaRecovery {
            try retirement.requireUnadmittedReturn()
            try requireCurrentOwner(owner)
            try retirement.requireUnadmittedControlsAbsent(
                applicationSupportURL: applicationSupportURL,
                coordinator: owner.coordinator, writer: owner.writer)
            removeOriginalOperation(ticket.operationID)
            pendingEraseDrainProof = nil
            deferredEraseCoordinator = nil
            operationOwnedWriter = nil
            preparedStartup = PreparedStartup(owner: returnStartup.owner,
                recovery: returnStartup.recovery,
                unadmittedEraseCaptureOperationID: ticket.operationID)
            operationID = nil
            operationKind = nil
            operationAuthorization = nil
            isRunning = false
            // startIfNeeded(accessGate:) handles preparedStartup before its
            // hasStarted guard. It revalidates genuine current access, restarts
            // commerce and publishes this exact retained writer through the
            // existing publishPreparedStartup path; no old capability revives.
            route = .checking
        }
    }

    /// The lifecycle may release a reservation only after the service's real
    /// no-effect proof.  This router consumes that service-issued receipt and
    /// clears only its exact original operation, never a newer ticket.
    func cancelAbortedErase(
        _ ticket: OriginalOperationTicket,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard ticket.owner === originalOperationOwner,
              let state = originalOperations[ticket.operationID],
              state.owner === ticket.owner, state.mint === ticket.mint,
              state.kind == .erase,
              state.eraseSubject == receipt.subject,
              state.acknowledgedReservation == receipt.reservation,
              state.sourceGenerationID == receipt.originalGenerationID,
              operationID == ticket.operationID || operationID == nil,
              let owner = retainedEraseRetirementOperation,
              owner.ticket.mint === ticket.mint else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try owner.requireNoRetirementResourcesForAbort()
        try owner.inventory.armAbortedOriginalReaderRetirement(operation: owner)
        pendingAbortedOriginalReaderRetirements.append(
            PendingAbortedOriginalReaderRetirement(operation: owner, receipt: receipt))
        retainedEraseRetirementOperation = nil
        removeOriginalOperation(ticket.operationID)
        pendingEraseDrainProof = nil
        deferredEraseCoordinator = nil
        if operationID == ticket.operationID {
            operationID = nil
            operationKind = nil
            operationAuthorization = nil
            isRunning = false
        }
        retainOwnedWriter(operationOwnedWriter)
        operationOwnedWriter = nil
        pendingErasedActivation = nil
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
    }

    private func startupAuthorization(_ accessGate: any AppAccessGatePortV1) async throws -> StartupAuthorization {
#if DEBUG
        guard !abandonedOriginalEraseForColdRestart else {
            throw AppAccessContractFailureV1.staleAttempt
        }
#endif
        // A point-in-time port permit cannot fence relock/unlock ABA. Production
        // startup must capture the concrete gate's original read epoch.
        guard let gate = accessGate as? AppAccessGateV1 else {
            _ = try await accessGate.requireContentAccess(for: .startupRecovery)
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try bindStartupAccessGate(gate)
        return .content(gate, try await gate.beginContentRead(for: .startupRecovery))
    }
#if DEBUG
    private func beginRuntimeObservation(_ phase: StartupRuntimeObservationPhaseV1) {
        let now = DispatchTime.now().uptimeNanoseconds
        if var current = runtimeObservation, current.endedAtUptimeNanoseconds == nil {
            current.endedAtUptimeNanoseconds = now
            runtimeObservation = current
        }
        runtimeObservation = StartupRuntimeObservationV1(
            phase: phase,
            startedAtUptimeNanoseconds: now,
            endedAtUptimeNanoseconds: nil
        )
    }

    private func endRuntimeObservation(_ phase: StartupRuntimeObservationPhaseV1) {
        guard var current = runtimeObservation,
              current.phase == phase,
              current.endedAtUptimeNanoseconds == nil else {
            return
        }
        current.endedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        runtimeObservation = current
    }
#endif

    private func runStartup(authorization: StartupAuthorization?, coldEraseService: EraseAllService? = nil) async {
#if DEBUG
        if abandonedOriginalEraseForColdRestart {
            route = .maintenance(.eraseInconsistent)
            return
        }
#endif
        guard !isRunning else {
            return
        }
#if DEBUG
        beginRuntimeObservation(.preflight)
#endif
        lastStartupAccessFailure = nil
        do { try await authorization?.validate() }
        catch { lastStartupAccessFailure = error; return }
        guard !isRunning else { return }
        invalidateOperationAndPublishedWriter()
        if let value = retainedEraseRetirementOperation {
            if value.detached { route = .eraseCleanupPending(.retiring(value)) }
            else if let actual = originalOperations[value.ticket.operationID]?.source.coordinator {
                route = .eraseCleanupPending(.preparing(actual))
            } else { route = .maintenance(.eraseInconsistent) }
            return
        }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.dataPointerInvalid)
            return
        }
        do {
            try settleAbortedOriginalReaderRetirements()
        } catch {
            // Keep the exact operation and handles for a later checked retry.
            // A fresh startup must not open a second reader over this cohort.
            lastStartupAccessFailure = error
            route = .maintenance(.eraseInconsistent)
            return
        }
        if let startupPreparationFailure {
            route = .maintenance(startupPreparationFailure)
            return
        }
        if let pendingEraseDrainProof {
            if originalOperations.values.contains(where: { $0.kind == .erase }) {
                if let deferredEraseCoordinator {
                    route = .eraseCleanupPending(.preparing(deferredEraseCoordinator))
                } else {
                    route = .maintenance(.eraseInconsistent)
                }
                return
            }
            guard pendingEraseDrainProof.isDrained else {
                if let deferredEraseCoordinator {
                    route = .eraseCleanupPending(.preparing(deferredEraseCoordinator))
                } else {
                    route = .maintenance(.eraseInconsistent)
                }
                return
            }
            self.pendingEraseDrainProof = nil
            deferredEraseCoordinator = nil
        }

        guard !maintenanceOperationsUncertain else {
            route = .maintenance(.restoreInconsistent)
            return
        }
        let operation = beginOperation(.startup, authorization: authorization)
        clearMaintenanceFrameForNewOpening()
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        defer { endOperation(operation) }
        var openedSession: StoreGenerationSession?
        var unpublishedOwner: OwnedWriter?
        var coldFreshOwner: EraseFreshAdoptionOwnerV1?

        do {
            try await requireCurrentOperationAndAccess(operation)
            // The aggregate already proved the ordinary restore/erase owners
            // clear before reservation. Their abandoned-staging cleanup must
            // not mistake its bound candidate for an ordinary restore.
            let resumesAggregate = try generationFactory.hasAggregateMigrationReservation()
#if DEBUG
            beginRuntimeObservation(.erase)
#endif
            didBeginStep(.erase)
            do {
                if !resumesAggregate {
                    coldFreshOwner = try await reconcileColdErase(operation: operation,
                        authorization: authorization, service: coldEraseService ?? EraseAllService(
                            applicationSupportURL: applicationSupportURL, fileManager: fileManager))
                }
            } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.eraseInconsistent
            }
            try await requireCurrentOperationAndAccess(operation)
            // The Erase observation preceded the access await. Recheck its
            // original retained directory before restore/current-open work.
            do {
                try await reproveEmptyNoWorkBeforeOrdinaryEffects()
            } catch {
                throw StartupMaintenanceReason.eraseInconsistent
            }

#if DEBUG
            beginRuntimeObservation(.restore)
#endif
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
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.restoreInconsistent
            }
            try await requireCurrentOperationAndAccess(operation)
            do {
                try await reproveEmptyNoWorkBeforeOrdinaryEffects()
            } catch {
                throw StartupMaintenanceReason.eraseInconsistent
            }

#if DEBUG
            currentOpenBoundaryForTesting = "session-select"
            beginRuntimeObservation(.currentOpen)
#endif
            didBeginStep(.currentOpen)
            let session: StoreGenerationSession
            if let restoredSession {
                session = restoredSession
            } else if let coldFreshOwner {
                if let retained = coldFreshOwner.readySession {
                    session = retained
                } else { session = try coldFreshOwner.constructColdReader() }
            } else {
#if DEBUG
                currentOpenBoundaryForTesting = "factory-open"
#endif
                let result = try await generationFactory.openForStartup(validateContinuation: {
                    try await self.requireCurrentOperationAndAccess(operation)
                }, recoverOriginalSource: { authority in
                    try await self.requireCurrentOperationAndAccess(operation)
                    try await self.recoverOriginalSource(authority, operation: operation)
                    try await self.requireCurrentOperationAndAccess(operation)
                })
                try await requireCurrentOperationAndAccess(operation)
                do {
                    try await reproveEmptyNoWorkBeforeOrdinaryEffects()
                } catch {
                    throw StartupMaintenanceReason.eraseInconsistent
                }
                switch result {
                case .ready(let current): session = current
                case .awaitingIndependentValidation(let pending):
#if DEBUG
                    endRuntimeObservation(.currentOpen)
#endif
                    route = .awaitingIndependentValidation(pending)
                    return
                }
            }
            openedSession = session
            // The exact opened reader is live here; every later Router
            // recovery await must be measured against this original frame.
#if DEBUG
            currentOpenBoundaryForTesting = "maintenance-frame"
#endif
            try captureMaintenanceFrame(session)
            do {
#if DEBUG
                currentOpenBoundaryForTesting = "lease-reconcile"
#endif
                try reconcileGenerationLeasesForStartup()
            } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.dataPointerInvalid
            }
#if DEBUG
            beginRuntimeObservation(.fieldDraft)
#endif
            didBeginStep(.fieldDraft)
            do {
                _ = try DraftCommitSagaRecoveryV1(
                    modelContext: session.modelContext
                ).reconcile()
            } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.fieldDraftInconsistent
            }

#if DEBUG
            beginRuntimeObservation(.finalization)
#endif
            didBeginStep(.finalization)
            // V2 effects and receipts are one transaction, so the journal is
            // already coherent before file-intent recovery. Keep this sole
            // writer unpublished until every recovery step succeeds.
            // Installing the writer revalidates the canonical mutation journal.
            // An integrity failure (e.g. receiptHistoryCorrupt) keeps the writer
            // uninstalled and routes to the finalization-step maintenance reason.
            let coordinator: StoreSessionCoordinator
            do {
                if let coldFreshOwner {
                    if let retained = coldFreshOwner.readyCoordinator {
                        coordinator = retained
                    } else {
                        let profiles = try lifecycleProfileRegistry
                            ?? WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
                        coordinator = try coldFreshOwner.constructColdWriter(session: session,
                            lifecycleProfileRegistry: profiles)
                    }
                    guard let ordinary = coldFreshOwner.ordinaryFactory else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    generationFactory = ordinary
                } else {
                    coordinator = try StoreSessionCoordinator(validatingSession: session,
                        lifecycleProfileRegistry: lifecycleProfileRegistry)
                }
            } catch let reason as StartupMaintenanceReason {
                throw reason
            } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.finalizationInconsistent
            }
            let owner = OwnedWriter(coordinator)
            unpublishedOwner = owner
            operationOwnedWriter = owner
            maintenanceFrameHadInstalledWriter = true
            do {
                try await retireCurrentPrivatePreparations(session: session, operation: operation, owner: owner)
                let finalizationRecovery = FinalizationRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    workspaceWriter: owner.writer,
                    lifecycleProfileRegistry: coordinator.lifecycleProfileRegistry,
                    retainedStartupStore: maintenanceFinalizationStore)
                _ = try await finalizationRecovery.reconcile()
                if let store = maintenanceFinalizationStore {
                    let receipt = try await store.startupRecoveryJournalReceipt()
                    try recordMaintenanceOperationsRecoveryEffect(receipt)
                }
                try await closeMaintenanceFinalizationOwnerChecked()
            } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.finalizationInconsistent
            }
            try await requireCurrentOperationAndAccess(operation, owner: owner)

#if DEBUG
            beginRuntimeObservation(.deletion)
#endif
            didBeginStep(.deletion)
            do {
                try requireBeforeMaintenanceOperationsEffect()
                let descriptorOwner: RestoreMaintenanceOperationsDescriptorOwnerV1?
                if maintenanceControlFrame != nil {
                    descriptorOwner = RestoreMaintenanceOperationsDescriptorOwnerV1()
                    maintenanceDeletionDescriptorOwner = descriptorOwner
                } else { descriptorOwner = nil }
                let deletionRecovery = WholeSignDeletionService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager,
                    trackStartupOperationsCreation: maintenanceControlFrame != nil,
                    startupDescriptorOwner: descriptorOwner)
                maintenanceDeletionService = deletionRecovery
                if maintenanceControlFrame != nil {
                    try recordMaintenanceOperationsEffect {
                        try descriptorOwner?.requireOpen()
                        return try deletionRecovery.startupOperationsReceipt()
                    }
                    maintenanceOperationsUncertain = true
                }
                _ = try await deletionRecovery.reconcile()
                if maintenanceControlFrame != nil {
                    try recordMaintenanceOperationsRecoveryEffect(
                        deletionRecovery.startupRecoveryJournalReceipt())
                }
                try closeMaintenanceDeletionOwnerChecked()
            } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.finalizationInconsistent
            }
            try await requireCurrentOperationAndAccess(operation, owner: owner)

#if DEBUG
            beginRuntimeObservation(.media)
#endif
            didBeginStep(.media)
            do {
                try await recoverCurrentMedia(session: session, operation: operation, owner: owner)
            } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.mediaInconsistent
            }
            try await requireCurrentOperationAndAccess(operation, owner: owner)

#if DEBUG
            beginRuntimeObservation(.pdf)
#endif
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
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.finalizationInconsistent
            }

#if DEBUG
            beginRuntimeObservation(.sourceHistory)
#endif
            _ = try coordinator.workspaceWriter.sourceMutationHistorySnapshot()
            try await requireCurrentOperationAndAccess(operation, owner: owner)
            if authorization?.permitsPublication == false {
                if let coldFreshOwner { try consumeColdStartupOwnership(coldFreshOwner,
                    session: session, coordinator: coordinator) }
                try reproveEmptyNoWorkBeforePublication(
                    operation: operation, owner: owner, close: false)
                preparedStartup = PreparedStartup(owner: owner, recovery: reportRecoveryService)
                operationOwnedWriter = nil
                return
            }
#if DEBUG
            beginRuntimeObservation(.diagnostics)
#endif
            await diagnosticsStore.prepare()
            try await requireCurrentOperationAndAccess(operation, owner: owner)
#if DEBUG
            beginRuntimeObservation(.commerce)
#endif
            do {
                try await installCommerceProcessor(operation: operation, owner: owner)
            } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
                throw StartupMaintenanceReason.finalizationInconsistent
            }
            try await requireCurrentOperationAndAccess(operation, owner: owner)
            if let coldFreshOwner { try consumeColdStartupOwnership(coldFreshOwner,
                session: session, coordinator: coordinator) }
            try reproveEmptyNoWorkBeforePublication(
                operation: operation, owner: owner, close: true)
            publishedWriter = owner
            operationOwnedWriter = nil
#if DEBUG
            beginRuntimeObservation(.ready)
#endif
            route = .ready(
                coordinator,
                diagnosticsStore,
                reportRecoveryService
            )
#if DEBUG
            endRuntimeObservation(.ready)
#endif
        } catch {
#if DEBUG
                reportStartupFailureForTesting(error)
#endif
            if let coldFreshOwner {
                // Actual fresh attempts own construction failures. Generic
                // writer cleanup cannot forget a partially published token.
                coldFreshOwner.markFailedColdConstruction()
                openedSession = nil
                unpublishedOwner = nil
                operationOwnedWriter = nil
                maintenanceRestoreSession = nil
                maintenanceEraseSession = nil
                stopCommerce()
                hasStarted = false
                if operationID == operation { route = .maintenance(.eraseInconsistent) }
                return
            }
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
            if lastStartupAccessFailure != nil {
                maintenanceRestoreSession = nil
                maintenanceEraseSession = nil
                hasStarted = false
                route = .checking
                return
            }
            if let reason = error as? StartupMaintenanceReason {
#if DEBUG
                if openedSession == nil {
                    FileHandle.standardError.write(Data(
                        "V23_RESTORE_MAINTENANCE_ELIGIBILITY_V1 first=no-opened-session\n".utf8))
                }
                do {
                    try beforeMaintenanceClearObservationForTesting?()
                } catch {
                    maintenanceRestoreSession = nil
                    maintenanceEraseSession = nil
                    route = .maintenance(reason)
                    return
                }
#endif
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

    /// Notification repair uses its separate startup-only capability to finish
    /// canonical recovery. The resulting sole owner stays covered and cannot
    /// activate commerce or publish a content route through that capability.
    func notificationSource(authorization: NotificationOperationAuthorizationV1) async throws -> ProductionMyDaySourceProviderV1 {
        guard startupAccessGate === authorization.gate else { throw AppAccessContractFailureV1.accessDenied }
        try await authorization.validateRead()
        let owner: OwnedWriter
        switch authorization.proof {
        case .content:
            guard let publishedWriter,
                  case .ready(let coordinator, _, _) = route,
                  coordinator === publishedWriter.coordinator else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            owner = publishedWriter
        case .toggle:
            if let publishedWriter,
               case .ready(let coordinator, _, _) = route,
               coordinator === publishedWriter.coordinator {
                owner = publishedWriter
            } else if let preparedStartup,
                      publishedWriter == nil,
                      !isRunning,
                      case .checking = route {
                owner = preparedStartup.owner
            } else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        case .repair:
            try await authorization.validateStartupRecovery()
            if preparedStartup == nil {
                guard publishedWriter == nil, !isRunning else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                await runStartup(authorization: .configuration(authorization))
            }
            try await authorization.validateStartupRecovery()
            if let lastStartupAccessFailure { throw lastStartupAccessFailure }
            guard let preparedStartup else { throw AppAccessContractFailureV1.configurationUnknown }
            owner = preparedStartup.owner
        }
        try requireCurrentOwner(owner)
        let source = ProductionMyDaySourceProviderV1(session: owner.coordinator, accessGate: authorization.gate)
        try await authorization.validateRead()
        try requireCurrentOwner(owner)
        return source
    }

    private func publishPreparedStartup(_ prepared: PreparedStartup, authorization: StartupAuthorization) async throws {
        guard authorization.permitsPublication, !isRunning,
              preparedStartup?.owner.writer === prepared.owner.writer else {
            throw AppAccessContractFailureV1.accessDenied
        }
        try await authorization.validate()
        guard !isRunning, preparedStartup?.owner.writer === prepared.owner.writer else {
            throw AppAccessContractFailureV1.accessDenied
        }
        let operation = beginOperation(.startup, authorization: authorization)
        operationOwnedWriter = prepared.owner
        defer { endOperation(operation) }
        do {
            try await requireCurrentOperationAndAccess(operation, owner: prepared.owner)
            try reproveEmptyNoWorkBeforePublication(
                operation: operation, owner: prepared.owner, close: false)
            await diagnosticsStore.prepare()
            try await requireCurrentOperationAndAccess(operation, owner: prepared.owner)
            try reproveEmptyNoWorkBeforePublication(
                operation: operation, owner: prepared.owner, close: false)
            try await installCommerceProcessor(operation: operation, owner: prepared.owner)
            try await requireCurrentOperationAndAccess(operation, owner: prepared.owner)
            try reproveEmptyNoWorkBeforePublication(
                operation: operation, owner: prepared.owner, close: false)
            if let captureOperationID = prepared.unadmittedEraseCaptureOperationID {
                try prepared.owner.coordinator.resumeWholeSignDeletionAfterAuthenticatedEraseReturn(
                    expectedWriter: prepared.owner.writer,
                    captureOperationID: captureOperationID)
            }
            try reproveEmptyNoWorkBeforePublication(
                operation: operation, owner: prepared.owner, close: true)
            publishedWriter = prepared.owner
            operationOwnedWriter = nil
            preparedStartup = nil
            lastStartupAccessFailure = nil
            route = .ready(prepared.owner.coordinator, diagnosticsStore, prepared.recovery)
        } catch {
            guard operationID == operation else { throw error }
            invalidateOperationAndPublishedWriter()
            _ = resolvePendingWriterCleanup()
            hasStarted = false
            route = .checking
            throw error
        }
    }

    /// The caller raises its visual cover synchronously before forwarding the
    /// lifecycle event to the actor gate. Retain a settled owner only for a
    /// transient cover or completed repair; real revocation retires its lease.
    func pauseForAppAccess(discardPrepared: Bool = true) {
        stopCommerce()
        if pendingRestoreReaderTransition != nil ||
            originalOperations.values.contains(where: {
                $0.kind == .restore && $0.restoreSourceExit != nil
            }) {
            route = .checking
            return
        }
        if retainedEraseRetirementOperation != nil {
            invalidateOperationAndPublishedWriter()
            return
        }
        if let originalErase = originalOperations.first(where: { $0.value.kind == .erase }) {
            if originalErase.value.postAdoptionStartup,
               operationID == nil || operationID == originalErase.key,
               let activation = pendingErasedActivation,
               activation.operationID == originalErase.key,
               activation.owner.coordinator === originalErase.value.source.coordinator,
               operationOwnedWriter?.writer === activation.owner.writer {
                // The receipt-backed replacement stays privately owned after
                // the first revocation. Repeated inactive/background events
                // must be idempotent rather than retiring its only activation.
                if operationID == originalErase.key {
                    operationID = nil
                    operationKind = nil
                    operationAuthorization = nil
                    isRunning = false
                }
                maintenanceRestoreSession = nil
                maintenanceEraseSession = nil
                route = .checking
                return
            }
            if operationID == originalErase.key, isRunning {
                // An admitted service may be suspended in its lifecycle hook.
                // The gate has already covered and revoked content; retiring
                // this private owner would make its exact revalidation fail
                // before any durable Erase intent exists.  Keep the original
                // operation/owner/activation until that service transfers or
                // reports its own ticketed failure.
                maintenanceRestoreSession = nil
                maintenanceEraseSession = nil
                route = .checking
                return
            }
            // A background transition revokes content, but it must not erase
            // the original physical-cleanup identity or its weak drain proof.
            // Retire writers while leaving the ticket available for the
            // service's exact failure/deferred continuation.
            retainOwnedWriter(operationOwnedWriter)
            retainOwnedWriter(pendingErasedActivation?.owner)
            retainOwnedWriter(publishedWriter)
            operationOwnedWriter = nil
            pendingErasedActivation = nil
            publishedWriter = nil
            if operationID == originalErase.key { operationID = nil }
            operationKind = nil
            operationAuthorization = nil
            isRunning = false
            maintenanceRestoreSession = nil
            maintenanceEraseSession = nil
            route = deferredEraseCoordinator.map { .eraseCleanupPending(.preparing($0)) } ?? .checking
            return
        }
        if isRunning || discardPrepared {
            invalidateOperationAndPublishedWriter()
            _ = resolvePendingWriterCleanup()
        } else if case .ready(let coordinator, _, let recovery) = route,
                  let publishedWriter, publishedWriter.coordinator === coordinator {
            preparedStartup = PreparedStartup(owner: publishedWriter, recovery: recovery)
            self.publishedWriter = nil
        }
        hasStarted = false
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
    }

    private func stopCommerce() {
        entitlementProcessor?.stop()
        entitlementProcessor = nil
    }

    private func beginOperation(_ kind: OperationKind, authorization: StartupAuthorization? = nil) -> UUID {
        temporalNormalizationOperation?.revoke()
        temporalNormalizationOperation = nil
        temporalColdOperation?.revoke()
        temporalColdOperation = nil
        let id = UUID()
        operationID = id
        operationKind = kind
        operationAuthorization = authorization
        isRunning = true
        stopCommerce()
        return id
    }

    private func endOperation(_ id: UUID) {
        guard operationID == id else { return }
        temporalNormalizationOperation?.revoke()
        temporalNormalizationOperation = nil
        temporalColdOperation?.revoke()
        temporalColdOperation = nil
        if originalOperations[id]?.kind == .restore {
            removeOriginalOperation(id)
        }
        operationID = nil
        operationKind = nil
        operationAuthorization = nil
        operationOwnedWriter = nil
        isRunning = false
    }

    private func requireCurrentOperation(_ id: UUID, owner: OwnedWriter? = nil) throws {
        guard operationID == id, isRunning else { throw OperationFailure.superseded }
        if let owner { try requireCurrentOwner(owner) }
    }

    private func requireCurrentOwner(_ owner: OwnedWriter) throws {
        guard owner.coordinator.workspaceWriter === owner.writer,
              owner.coordinator.generationID == owner.generationID,
              try generationFactory.currentGenerationID() == owner.generationID else {
            throw OperationFailure.superseded
        }
        _ = try owner.writer.sourceMutationHistorySnapshot()
    }

    private func requireCurrentOperationAndAccess(_ id: UUID, owner: OwnedWriter? = nil) async throws {
        try requireCurrentOperation(id)
        if let authorization = operationAuthorization {
            do { try await authorization.validate() }
            catch {
                if operationID == id { lastStartupAccessFailure = error }
                throw error
            }
        }
        try requireCurrentOperation(id, owner: owner)
    }

    private func requireCurrentPostAdoptionExecution(
        operation: UUID,
        execution: PostAdoptionExecution?
    ) throws {
        guard let execution else { return }
        try requireCurrentPostAdoptionClaim(
            operation: operation,
            ticket: execution.ticket,
            executionID: execution.executionID
        )
    }

    private func requireCurrentPostAdoptionClaim(
        operation: UUID,
        ticket: OriginalOperationTicket,
        executionID: UUID
    ) throws {
        guard ticket.owner === originalOperationOwner,
              ticket.operationID == operation,
              let state = originalOperations[operation],
              state.owner === ticket.owner,
              state.mint === ticket.mint,
              state.postAdoptionStartup,
              state.postAdoptionExecutionID == executionID else {
            throw OperationFailure.superseded
        }
    }

    private func suspendPostAdoptionExecutionIfCurrent(
        operation: UUID,
        ticket: OriginalOperationTicket,
        executionID: UUID
    ) {
        guard operationID == operation, isRunning else { return }
        do {
            try requireCurrentPostAdoptionClaim(
                operation: operation, ticket: ticket, executionID: executionID
            )
        } catch {
            return
        }
        operationID = nil
        operationKind = nil
        operationAuthorization = nil
        isRunning = false
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
    }

    private func isCurrentPostAdoptionExecution(
        operation: UUID,
        execution: PostAdoptionExecution?
    ) -> Bool {
        guard operationID == operation, isRunning else { return false }
        do {
            try requireCurrentPostAdoptionExecution(operation: operation, execution: execution)
            return true
        } catch {
            return false
        }
    }

    private func requireCurrentOperationAndContent(
        _ operation: UUID,
        owner: OwnedWriter,
        execution: PostAdoptionExecution?
    ) throws {
        let validate: () throws -> Void = {
            try self.requireCurrentPostAdoptionExecution(
                operation: operation, execution: execution
            )
            if let execution {
                self.willReadPostAdoptionCanonicalContent(execution.executionID)
            }
            try self.requireCurrentOperation(operation, owner: owner)
        }
        if let execution {
            try execution.contentReadToken.withContentRead(
                for: .startupRecovery, validate
            )
        } else {
            try validate()
        }
    }

    private func requireCurrentOperationAccessAndContent(
        _ operation: UUID,
        owner: OwnedWriter,
        execution: PostAdoptionExecution?
    ) async throws {
        try requireCurrentOperation(operation)
        if let authorization = operationAuthorization {
            do { try await authorization.validate() }
            catch {
                guard isCurrentPostAdoptionExecution(
                    operation: operation, execution: execution
                ) else { throw error }
                lastStartupAccessFailure = error
                throw error
            }
        }
        try requireCurrentOperationAndContent(
            operation, owner: owner, execution: execution
        )
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
        if pendingRestoreReaderTransition != nil ||
            originalOperations.values.contains(where: {
                $0.kind == .restore && $0.restoreSourceExit != nil
            }) {
            route = .checking
            return
        }
#if DEBUG
        if abandonedOriginalEraseForColdRestart {
            route = .maintenance(.eraseInconsistent)
            return
        }
#endif
        if let value = retainedEraseRetirementOperation {
            if var state = originalOperations[value.ticket.operationID] {
                state.postAdoptionExecutionID = nil
                originalOperations[value.ticket.operationID] = state
            }
            operationID = nil
            operationKind = nil
            operationAuthorization = nil
            isRunning = false
            stopCommerce()
            if value.detached {
                // The fresh owner retains any actual unpublished allocation.
                operationOwnedWriter = nil
                route = .eraseCleanupPending(.retiring(value))
            } else if let actual = originalOperations[value.ticket.operationID]?.source.coordinator {
                actual.workspaceWriter.invalidate()
                // Keep the original coordinator and actual EX acquisition;
                // ordinary close here could deadlock or lose failure ownership.
                route = .eraseCleanupPending(.preparing(actual))
            } else {
                route = .maintenance(.eraseInconsistent)
            }
            return
        }
        retainOwnedWriter(eraseCleanupRetirement?.owner)
        if let operationID { removeOriginalOperation(operationID) }
        operationID = nil
        operationKind = nil
        operationAuthorization = nil
        isRunning = false
        stopCommerce()
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        retainOwnedWriter(operationOwnedWriter)
        retainOwnedWriter(pendingErasedActivation?.owner)
        retainOwnedWriter(publishedWriter)
        retainOwnedWriter(preparedStartup?.owner)
        eraseCleanupRetirement = nil
        operationOwnedWriter = nil
        pendingErasedActivation = nil
        publishedWriter = nil
        preparedStartup = nil
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

    private func settleAbortedOriginalReaderRetirements() throws {
        guard !hasPendingWriterCleanup else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        for pending in pendingAbortedOriginalReaderRetirements {
            try pending.operation.requireCheckedSourceWriterReleaseForAbortedReaderRetirement(
                receipt: pending.receipt)
            try pending.operation.inventory.closeAbortedOriginalReadersAfterDrain()
        }
        pendingAbortedOriginalReaderRetirements.removeAll()
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
        guard startupAccessGate == nil else { return }
        guard !isRunning, pendingEraseDrainProof == nil else {
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
        guard startupAccessGate == nil else { return }
        await beginErasedSessionActivationCore(session, coordinator: coordinator)
    }

    func beginErasedSessionActivation(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator,
        ticket: OriginalOperationTicket
    ) async throws {
        if operationID == nil, !isRunning,
           let retirement = eraseCleanupRetirement,
           retirement.operationID == ticket.operationID,
           retirement.released,
           retirement.owner.coordinator === coordinator,
           retirement.owner.writer === coordinator.workspaceWriter,
           retirement.session.generationID == session.generationID,
           retirement.session.generationRootURL.standardizedFileURL
            == session.generationRootURL.standardizedFileURL,
           deferredEraseCoordinator === coordinator,
           ticket.owner === originalOperationOwner,
           let retained = originalOperations[ticket.operationID],
           retained.owner === ticket.owner, retained.mint === ticket.mint,
           retained.kind == .erase {
            guard try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: applicationSupportURL) else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            operationID = ticket.operationID
            operationKind = .erase
            operationAuthorization = nil
            isRunning = true
        }
        let state = try await validateOriginalOperation(ticket, kind: .erase)
        guard state.source.coordinator === coordinator,
              state.sourceGenerationID != session.generationID else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        if let retirement = eraseCleanupRetirement {
            // A second activation is only the exact completed cleanup's fresh
            // binding. Keep the retired owner on failure so receipt-backed
            // recovery can retry without repeating the physical Erase.
            try requireEraseCleanupOwner(retirement, ticket: ticket)
            guard retirement.released,
                  retirement.owner.coordinator === coordinator,
                  session.generationID == retirement.session.generationID,
                  session.generationRootURL.standardizedFileURL
                    == retirement.session.generationRootURL.standardizedFileURL,
                  BackupRestoreService.isEmptyCurrent(session.modelContext),
                  try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: applicationSupportURL),
                  resolvePendingWriterCleanup() else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            do { try coordinator.activateAfterErasedCleanup(session: session) }
            catch {
                // Preserve an uninstalled replacement's failed release as well
                // as the original ticket; never hide either cleanup failure.
                retainWriterCleanup(error, owner: nil)
                throw error
            }
            let owner = OwnedWriter(coordinator)
            generationFactory = StoreGenerationFactory(
                applicationSupportURL: applicationSupportURL, fileManager: fileManager
            )
            operationOwnedWriter = owner
            pendingErasedActivation = (owner, session, ticket.operationID)
            publishedWriter = nil
            deferredEraseCoordinator = nil
            eraseCleanupRetirement = nil
            route = .checking
            return
        }
        // The admission token is expected to be revoked by the lifecycle
        // reservation.  Its identity remains bound in state; no replacement
        // permit is minted here.
        if let deferredEraseCoordinator {
            guard deferredEraseCoordinator === coordinator else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            // Consume only the exact deferred-owner marker. This is not a
            // fresh activation: ticket and drain proof remain continuous.
            self.deferredEraseCoordinator = nil
        }
        await beginErasedSessionActivationCore(session, coordinator: coordinator)
        _ = try await validateOriginalOperation(ticket, kind: .erase)
    }

    private func beginErasedSessionActivationCore(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator
    ) async {
        guard deferredEraseCoordinator == nil,
              operationID != nil || pendingEraseDrainProof == nil else {
            failClosedErase()
            return
        }
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
            eraseCleanupRetirement = EraseCleanupRetirement(
                owner: owner, session: session, operationID: operation
            )
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
        guard startupAccessGate == nil else { return }
        _ = await finishErasedSessionActivationCore(
            session, coordinator: coordinator, postStartupCompletion: nil
        )
    }

    func finishErasedSessionActivation(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator,
        ticket: OriginalOperationTicket,
        accessGate: AppAccessGateV1
    ) async throws {
        var state: OriginalOperationState
        if operationID == nil,
           let retained = originalOperations[ticket.operationID],
           ticket.owner === originalOperationOwner,
           retained.owner === ticket.owner, retained.mint === ticket.mint,
           retained.kind == .erase, retained.postAdoptionStartup,
           pendingErasedActivation?.owner.coordinator === coordinator {
            operationID = ticket.operationID
            operationKind = .erase
            operationAuthorization = nil
            isRunning = true
            state = retained
        } else {
            state = try awaitlessValidateEraseTicket(ticket)
        }
        guard state.source.coordinator === coordinator,
              state.acknowledgedReservation != nil,
              let activation = pendingErasedActivation,
              activation.operationID == ticket.operationID,
              activation.owner.coordinator === coordinator,
              activation.session.generationID == session.generationID,
              activation.session.modelContext === session.modelContext,
              operationOwnedWriter?.writer === activation.owner.writer else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        // Claim this exact ticket execution before the first suspension. A
        // lifecycle pause can now revoke only this execution without leaving
        // an older running operation available to install a later token.
        state.postAdoptionStartup = true
        let executionID = UUID()
        state.postAdoptionExecutionID = executionID
        originalOperations[ticket.operationID] = state
        do {
            await beforePostAdoptionContentRead(executionID)
            try requireCurrentOperation(ticket.operationID)
            try requireCurrentPostAdoptionClaim(
                operation: ticket.operationID, ticket: ticket, executionID: executionID
            )
            let recoveryToken = try await accessGate.beginContentRead(for: .startupRecovery)
            try requireCurrentOperation(ticket.operationID)
            try requireCurrentPostAdoptionClaim(
                operation: ticket.operationID, ticket: ticket, executionID: executionID
            )
            try await accessGate.validateContentRead(recoveryToken, for: .startupRecovery)
            let execution = PostAdoptionExecution(
                ticket: ticket, executionID: executionID, contentReadToken: recoveryToken
            )
            try recoveryToken.withContentRead(for: .startupRecovery) {
                try requireCurrentPostAdoptionExecution(
                    operation: ticket.operationID, execution: execution
                )
                willReadPostAdoptionCanonicalContent(execution.executionID)
                try requireCurrentOperation(ticket.operationID, owner: activation.owner)
                operationAuthorization = .content(accessGate, recoveryToken)
            }
            let completed = await finishErasedSessionActivationCore(
                session, coordinator: coordinator, postAdoptionExecution: execution
            ) {
                try await accessGate.completePostEraseStartup(recoveryToken)
            }
            guard completed,
                  case let .ready(readyCoordinator, _, _) = route,
                  readyCoordinator === coordinator,
                  originalOperations[ticket.operationID] == nil else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        } catch {
            suspendPostAdoptionExecutionIfCurrent(
                operation: ticket.operationID, ticket: ticket, executionID: executionID
            )
            throw error
        }
    }

    private func finishErasedSessionActivationCore(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator,
        postAdoptionExecution: PostAdoptionExecution? = nil,
        postStartupCompletion: (@MainActor () async throws -> Void)?
    ) async -> Bool {
        guard let activation = pendingErasedActivation else {
            if let postAdoptionExecution,
               !isCurrentPostAdoptionExecution(
                operation: postAdoptionExecution.ticket.operationID,
                execution: postAdoptionExecution
               ) {
                return false
            }
            failClosedErase()
            return false
        }
        let operation = activation.operationID
        let owner = activation.owner
        var endsOperation = true
        defer {
            if endsOperation,
               isCurrentPostAdoptionExecution(
                operation: operation, execution: postAdoptionExecution
               ) {
                endOperation(operation)
            }
        }
        guard isCurrentPostAdoptionExecution(
            operation: operation, execution: postAdoptionExecution
        ) else { return false }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.eraseInconsistent)
            return false
        }
        let ownsActivatedWriter = owner.coordinator === coordinator
            && owner.writer === coordinator.workspaceWriter
            && activation.session.generationID == session.generationID
            && activation.session.modelContext === session.modelContext
        do {
            try requireCurrentOperationAndContent(
                operation, owner: owner, execution: postAdoptionExecution
            )
            let recoverCanonicalContent: () throws -> ReportRecoveryService = {
                try self.requireCurrentPostAdoptionExecution(
                    operation: operation, execution: postAdoptionExecution
                )
                if let postAdoptionExecution {
                    self.willReadPostAdoptionCanonicalContent(postAdoptionExecution.executionID)
                }
                try self.requireCurrentOperation(operation, owner: owner)
                if let fresh = self.freshEraseAdoption {
                    try fresh.requireReadyForPublication(session: session, coordinator: coordinator,
                        factory: self.generationFactory)
                } else {
                    guard self.pendingEraseDrainProof?.isDrained == true else {
                        throw StartupMaintenanceReason.eraseInconsistent
                    }
                }
                guard ownsActivatedWriter,
                      coordinator.generationID == session.generationID,
                      try self.generationFactory.currentGenerationID()
                        == session.generationID,
                      BackupRestoreService.isEmptyCurrent(session.modelContext),
                      self.noActiveJournal(
                        at: self.applicationSupportURL.appendingPathComponent(
                            "FieldEvidenceErase/erase.json"
                        )
                      ) else {
                    throw StartupMaintenanceReason.eraseInconsistent
                }
                try self.reconcileGenerationLeasesForStartup()
                let recovery = try self.makeActiveReportRecovery(
                    session: session,
                    coordinator: coordinator
                )
                try recovery.reconcileAtStartup()
                _ = try coordinator.workspaceWriter.sourceMutationHistorySnapshot()
                return recovery
            }
            let recovery: ReportRecoveryService
            if let postAdoptionExecution {
                recovery = try postAdoptionExecution.contentReadToken.withContentRead(
                    for: .startupRecovery, recoverCanonicalContent
                )
            } else {
                recovery = try recoverCanonicalContent()
            }
            await diagnosticsStore.prepare()
            try requireCurrentOperationAndContent(
                operation, owner: owner, execution: postAdoptionExecution
            )
            let diagnosticsAreZero = await diagnosticsStore.isExactlyZero()
            try requireCurrentOperationAndContent(
                operation, owner: owner, execution: postAdoptionExecution
            )
            guard diagnosticsAreZero else {
                throw StartupMaintenanceReason.eraseInconsistent
            }
            if let postStartupCompletion {
                try await postStartupCompletion()
                try await requireCurrentOperationAccessAndContent(
                    operation, owner: owner, execution: postAdoptionExecution
                )
            }
            try await installCommerceProcessor(
                operation: operation, owner: owner,
                postAdoptionExecution: postAdoptionExecution
            )
            let publishReady: () throws -> Void = {
                try self.requireCurrentPostAdoptionExecution(
                    operation: operation, execution: postAdoptionExecution
                )
                if let postAdoptionExecution {
                    self.willReadPostAdoptionCanonicalContent(postAdoptionExecution.executionID)
                }
                try self.requireCurrentOperation(operation, owner: owner)
                if let fresh = self.freshEraseAdoption {
                    try fresh.consumePublication(session: session, coordinator: coordinator,
                        factory: self.generationFactory)
                    self.freshEraseAdoption = nil
                    self.detachedEraseRetirement = nil
                    self.retainedEraseRetirementOperation = nil
                }
                self.pendingEraseDrainProof = nil
                self.deferredEraseCoordinator = nil
                self.pendingErasedActivation = nil
                self.operationOwnedWriter = nil
                self.publishedWriter = owner
                self.removeOriginalOperation(operation)
                endsOperation = false
                self.endOperation(operation)
                self.route = .ready(coordinator, self.diagnosticsStore, recovery)
            }
            if let postAdoptionExecution {
                try postAdoptionExecution.contentReadToken.withContentRead(
                    for: .startupRecovery, publishReady
                )
            } else {
                try publishReady()
            }
            return true
        } catch {
            guard isCurrentPostAdoptionExecution(
                operation: operation, execution: postAdoptionExecution
            ) else { return false }
            if originalOperations[operation]?.postAdoptionStartup == true {
                // Adoption has an authentic receipt and may be retried after
                // inactive/protected-data access settles.  Keep its original
                // ticket, writer and activation unpublished; failing closed
                // here would discard the only truthful continuation.
                endsOperation = false
                stopCommerce()
                route = .checking
                return false
            }
            retainWriterCleanup(error, owner: owner)
            _ = resolvePendingWriterCleanup()
            guard isCurrentPostAdoptionExecution(
                operation: operation, execution: postAdoptionExecution
            ) else { return false }
            failClosedErase()
            return false
        }
    }

    func deferErasedSessionCleanup(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator
    ) {
        guard startupAccessGate == nil else { return }
        deferErasedSessionCleanupCore(session, coordinator: coordinator)
    }

    func deferErasedSessionCleanup(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator,
        ticket: OriginalOperationTicket
    ) throws {
        _ = try awaitlessValidateEraseTicket(ticket)
        deferErasedSessionCleanupCore(session, coordinator: coordinator)
    }

    private func awaitlessValidateEraseTicket(
        _ ticket: OriginalOperationTicket
    ) throws -> OriginalOperationState {
        let matchesOperationKind: Bool
        switch operationKind { case .erase: matchesOperationKind = true; default: matchesOperationKind = false }
        guard ticket.owner === originalOperationOwner,
              let state = originalOperations[ticket.operationID],
              state.owner === ticket.owner, state.mint === ticket.mint,
              state.kind == .erase, operationID == ticket.operationID,
              matchesOperationKind, isRunning else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return state
    }

    private func deferErasedSessionCleanupCore(
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
            failClosedErase()
            return
        }
        deferredEraseCoordinator = coordinator
        pendingErasedActivation = nil
        operationOwnedWriter = nil
        publishedWriter = activation.owner
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .eraseCleanupPending(.preparing(coordinator))
    }

    private func requireEraseCleanupOwner(
        _ retirement: EraseCleanupRetirement,
        ticket: OriginalOperationTicket
    ) throws {
        let state = try awaitlessValidateEraseTicket(ticket)
        let owner = retirement.owner
        guard retirement.operationID == ticket.operationID,
              state.source.coordinator === owner.coordinator,
              state.acknowledgedReservation != nil,
              state.eraseSubject?.newGenerationID == owner.generationID,
              state.acknowledgedReservation?.subject == state.eraseSubject,
              owner.coordinator.workspaceWriter === owner.writer,
              owner.coordinator.generationID == owner.generationID,
              owner.generationID == retirement.session.generationID,
              owner.coordinator.modelContext === retirement.session.modelContext,
              owner.coordinator.generationRootURL.standardizedFileURL
                == retirement.session.generationRootURL.standardizedFileURL,
              try generationFactory.currentGenerationID() == owner.generationID,
              BackupRestoreService.isEmptyCurrent(retirement.session.modelContext),
              pendingEraseDrainProof?.isDrained == true else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    func prepareErasedSessionCleanup(_ ticket: OriginalOperationTicket) throws {
        guard let retirement = eraseCleanupRetirement else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireEraseCleanupOwner(retirement, ticket: ticket)
        guard !retirement.released else { return }
        // The structural owner is retained before invalidation. A failed close
        // is retried on this same handle, never through a now-invalid writer.
        try retirement.owner.coordinator.invalidateAndReleaseWriter()
        eraseCleanupRetirement?.released = true
    }

    /// An admitted cleanup failure retains its exact authority and private
    /// owner. Unlike generic failure this must not discard the original ticket.
    func suspendErasedSessionCleanup(_ ticket: OriginalOperationTicket) {
        if let value = retainedEraseRetirementOperation,
           value.ticket.owner === ticket.owner, value.ticket.mint === ticket.mint,
           value.ticket.operationID == ticket.operationID {
            invalidateOperationAndPublishedWriter()
            return
        }
        guard let retirement = eraseCleanupRetirement,
              retirement.operationID == ticket.operationID,
              (try? awaitlessValidateEraseTicket(ticket)) != nil else { return }
        deferredEraseCoordinator = retirement.owner.coordinator
        pendingErasedActivation = nil
        publishedWriter = nil
        endOperation(ticket.operationID)
        route = .eraseCleanupPending(.preparing(retirement.owner.coordinator))
    }

    /// Same-process recovery must continue the original erase subject through
    /// its lifecycle hook.  The caller supplies that real service route; this
    /// method never falls back to generic startup, which would manufacture a
    /// cold recovery while the old context is still live.
    func resumeDeferredErase(
        _ ticket: OriginalOperationTicket,
        reconcile: @escaping @MainActor () async throws -> StoreGenerationSession?
    ) async throws -> StoreGenerationSession? {
        guard let state = originalOperations[ticket.operationID],
              ticket.owner === originalOperationOwner,
              state.owner === ticket.owner, state.mint === ticket.mint,
              state.kind == .erase, deferredEraseCoordinator != nil,
              pendingEraseDrainProof?.isDrained == true,
              !isRunning else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        operationID = ticket.operationID
        operationKind = .erase
        // The lifecycle has already consumed the original read token.  Its
        // exact reservation, rather than a fresh token, admits this cleanup.
        operationAuthorization = nil
        isRunning = true
        do {
            try prepareErasedSessionCleanup(ticket)
            let session = try await reconcile()
            guard operationID == ticket.operationID else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            // Keep this original operation active so the returned session can
            // only reach the ticketed activation/finish edge.
            return session
        } catch {
            if operationID == ticket.operationID { endOperation(ticket.operationID) }
            throw error
        }
    }

    func failClosedErase() {
        invalidateOperationAndPublishedWriter()
        _ = resolvePendingWriterCleanup()
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .maintenance(.eraseInconsistent)
    }

    /// Compatibility entry for isolated, unbound tests.  A production-bound
    /// router requires the ticketed overload below.
    func activateRestoredSession(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator?
    ) async {
        guard startupAccessGate == nil else { return }
        try? await activateRestoredSessionCore(session, coordinator: coordinator, ticket: nil)
    }

    func activateRestoredSession(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator?,
        ticket: OriginalOperationTicket
    ) async throws -> UUID {
        let state = try await validateOriginalOperation(ticket, kind: .restore)
        guard pendingRestoreReaderTransition == nil,
              let source = state.restoreSourceExit,
              let intendedPointer = state.restoreTargetPointerData,
              let targetFactory = try? session.validatedOpeningFactoryForWriter(),
              !targetFactory.sharesRegistryProvider(with: generationFactory) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireOriginalRestoreSourceAtActivation(state,
            source: source, coordinator: coordinator)
        retainedRestoreTargetSessionOnFailure = session
        try await state.authorization.validate()
        guard pendingRestoreReaderTransition == nil,
              operationID == ticket.operationID,
              operationKind == .restored,
              originalOperations[ticket.operationID]?.mint === ticket.mint,
              originalOperations[ticket.operationID]?.restoreSourceExit === source,
              originalOperations[ticket.operationID]?.restoreTargetPointerData
                == intendedPointer else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireOriginalRestoreSourceAtActivation(state,
            source: source, coordinator: coordinator)
        try source.requireSourceUnchanged(stage: .activationBeforeTarget)
        try source.requireTargetPublished(session, openingFactory: targetFactory,
            intendedCanonicalPointer: intendedPointer)
        let targetReader = try session.retainedReaderForOriginalRestoreTransition(
            factory: targetFactory)
        let sourceWriterHandle: GenerationLeaseHandleV1?
        if let coordinator {
            guard let drainID = state.restoreDrainID,
                  let capturedHandle = state.restoreSourceWriterHandle,
                  let original = state.source.coordinator,
                  original === coordinator,
                  let originalOwner = publishedWriter,
                  originalOwner.coordinator === coordinator else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            retainedRestoreOldCoordinatorOnFailure = coordinator
            do {
                let reboundSource = try coordinator
                    .requireOriginalRestoreSourceAfterTargetPublication(
                        context: coordinator.modelContext,
                        generationID: state.sourceGenerationID,
                        factory: generationFactory,
                        expectedWriter: originalOwner.writer,
                        expectedWriterHandle: capturedHandle,
                        drainID: drainID)
                sourceWriterHandle = try coordinator.closeWriterForOriginalRestoreTransition(
                    source: reboundSource,
                    drainID: drainID, expectedWriter: originalOwner.writer)
            } catch {
                route = .maintenance(.restoreInconsistent)
                throw error
            }
            publishedWriter = nil
            operationOwnedWriter = nil
            retainedRestoreOldCoordinatorOnFailure = nil
        } else {
            sourceWriterHandle = nil
        }
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        let writerOwner = try RestoreWriterTransitionOwnerV1(
            operationID: ticket.operationID, targetSession: session,
            targetFactory: targetFactory, sourceReader: source.reader,
            sourceWriter: sourceWriterHandle, targetReader: targetReader)
        retainedRestoreWriterAttemptOnFailure = writerOwner
        let targetCoordinator: StoreSessionCoordinator
        do {
            targetCoordinator = try StoreSessionCoordinator.makeForOriginalRestoreTransition(
                owner: writerOwner,
                lifecycleProfileRegistry: lifecycleProfileRegistry)
        } catch {
            route = .maintenance(.restoreInconsistent)
            throw error
        }
        let boundSession = try targetCoordinator.requireOriginalEraseOpeningAuthority(
            factory: targetFactory)
        guard boundSession === session,
              operationID == ticket.operationID,
              originalOperations[ticket.operationID]?.mint === ticket.mint else {
            route = .maintenance(.restoreInconsistent)
            throw AppAccessContractFailureV1.staleAttempt
        }
        let pending = PendingRestoreReaderTransition(
            ticket: ticket, source: source, targetSession: session,
            targetFactory: targetFactory, targetReader: targetReader,
            writerOwner: writerOwner, targetCoordinator: targetCoordinator,
            targetWriter: targetCoordinator.restoreWriterLeaseHandleForTransition,
            originalFactory: generationFactory)
        pendingRestoreReaderTransition = pending
        retainedRestoreTargetSessionOnFailure = nil
        retainedRestoreWriterAttemptOnFailure = nil
        return pending.id
    }

    private func requireOriginalRestoreSourceAtActivation(
        _ state: OriginalOperationState,
        source: RestoreSourceReaderExitV1,
        coordinator: StoreSessionCoordinator?) throws {
        if let coordinator {
            guard state.source.coordinator === coordinator,
                  state.source.modelContext === coordinator.modelContext,
                  coordinator.generationID == state.sourceGenerationID,
                  case .ready(let published, _, _) = route,
                  published === coordinator,
                  publishedWriter?.coordinator === coordinator,
                  publishedWriter?.writer === coordinator.workspaceWriter else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        } else {
            guard state.source.coordinator == nil,
                  let sourceContext = state.source.modelContext,
                  let maintenanceRestoreSession,
                  case .maintenance = route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            try source.requireObservedMaintenanceSource(
                maintenanceRestoreSession, context: sourceContext,
                openingFactory: generationFactory)
        }
    }

    private func requirePendingRestore(
        _ pending: PendingRestoreReaderTransition
    ) async throws {
        guard pendingRestoreReaderTransition === pending,
              pending.ticket.owner === originalOperationOwner,
              operationID == pending.ticket.operationID,
              operationKind == .restored, isRunning,
              let state = originalOperations[pending.ticket.operationID],
              state.mint === pending.ticket.mint,
              state.restoreSourceExit === pending.source,
              state.restoreTargetPointerData != nil,
              pending.targetCoordinator.modelContext === pending.targetSession.modelContext,
              pending.targetCoordinator.generationID == pending.targetSession.generationID,
              pending.targetCoordinator.workspaceWriter === pending.writerOwner.constructedWriterForTransition else {
#if DEBUG
            let first: String
            if pendingRestoreReaderTransition !== pending { first = "pending-owner" }
            else if pending.ticket.owner !== originalOperationOwner { first = "ticket-owner" }
            else if operationID != pending.ticket.operationID || operationKind != .restored || !isRunning {
                first = "operation-state"
            } else if originalOperations[pending.ticket.operationID] == nil { first = "operation-record" }
            else if originalOperations[pending.ticket.operationID]?.mint !== pending.ticket.mint {
                first = "operation-mint"
            } else if originalOperations[pending.ticket.operationID]?.restoreSourceExit !== pending.source {
                first = "source-owner"
            } else if originalOperations[pending.ticket.operationID]?.restoreTargetPointerData == nil {
                first = "pointer-attestation"
            } else if pending.targetCoordinator.modelContext !== pending.targetSession.modelContext {
                first = "target-context"
            } else if pending.targetCoordinator.generationID != pending.targetSession.generationID {
                first = "target-generation"
            } else { first = "target-writer" }
            FileHandle.standardError.write(Data(
                "V23_RESTORE_PENDING_PROOF_V1 first=\(first)\n".utf8))
#endif
            throw AppAccessContractFailureV1.staleAttempt
        }
        #if DEBUG
        var proofStage = "target-reader-registry"
        #endif
        do {
            try pending.targetReader.requireExactRegistry(pending.writerOwner.registry)
            #if DEBUG
            proofStage = "target-reader-active"
            #endif
            try pending.writerOwner.registry.validateActive(
                pending.targetReader.token, requiredRole: .reader)
            #if DEBUG
            proofStage = "target-writer-active"
            #endif
            try pending.writerOwner.registry.validateActive(
                pending.targetWriter.token, requiredRole: .writer)
            #if DEBUG
            proofStage = "authorization"
            #endif
            try await state.authorization.validate()
        } catch {
            #if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_PENDING_PROOF_V1 first=\(proofStage)\n".utf8))
            #endif
            throw error
        }
        guard pendingRestoreReaderTransition === pending,
              operationID == pending.ticket.operationID,
              pending.ticket.owner === originalOperationOwner,
              originalOperations[pending.ticket.operationID]?.mint
                === pending.ticket.mint,
              originalOperations[pending.ticket.operationID]?.restoreSourceExit
                === pending.source,
              pending.targetCoordinator.workspaceWriter === pending.writerOwner.constructedWriterForTransition else {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_PENDING_PROOF_V1 first=postawait-association\n".utf8))
#endif
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    /// Only the exact pending ticket may advance the already restored B owner.
    /// A false result means that an actual A SwiftData alias is still alive;
    /// neither elapsed time nor sheet dismissal is an ownership witness.
    func resumeOriginalRestoreReaderTransition(_ id: UUID) async throws -> Bool {
        guard let pending = pendingRestoreReaderTransition,
              pending.id == id else {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_RESUME_PHASE_V1 first=pending-id\n".utf8))
#endif
            throw AppAccessContractFailureV1.staleAttempt
        }
        guard pending.phase == .waitingForOldAliases else {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_RESUME_PHASE_V1 first=pending-phase\n".utf8))
#endif
            throw AppAccessContractFailureV1.invalidTransition
        }
        do { try await requirePendingRestore(pending) }
        catch {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_RESUME_PHASE_V1 first=initial-pending-proof\n".utf8))
#endif
            throw error
        }
        let originalAliasesDrained = pending.source.hasDrainedOriginalAliases
#if DEBUG
        if !originalAliasesDrained {
            let aliases = pending.source.originalAliasPresenceForTesting()
            FileHandle.standardError.write(Data(
                "V23_RESTORE_ALIAS_DRAIN_V1 session=\(aliases.session) context=\(aliases.context) container=\(aliases.container) coordinator=\(aliases.coordinator) maintenance=\(maintenanceRestoreSession != nil) published=\(publishedWriter != nil) operation=\(operationOwnedWriter != nil) prepared=\(preparedStartup != nil) failureSource=\(retainedRestoreOldCoordinatorOnFailure != nil) failureTarget=\(retainedRestoreTargetSessionOnFailure != nil) failureWriter=\(retainedRestoreWriterAttemptOnFailure != nil)\n".utf8))
        }
#endif
        guard originalAliasesDrained else { return false }
#if DEBUG
        var resumeStage = "intended-pointer"
#endif
        do {
            guard let intendedPointer = originalOperations[
                pending.ticket.operationID]?.restoreTargetPointerData else {
                throw AppAccessContractFailureV1.staleAttempt
            }
#if DEBUG
            resumeStage = "target-published"
#endif
            try pending.source.requireTargetPublished(pending.targetSession,
                openingFactory: pending.targetFactory,
                intendedCanonicalPointer: intendedPointer)
#if DEBUG
            resumeStage = "source-close"
#endif
            try pending.source.closeAfterCheckedAliasDrain(
                targetRegistry: pending.writerOwner.registry,
                targetReader: pending.targetReader,
                targetWriter: pending.targetWriter,
                targetSession: pending.targetSession,
                targetFactory: pending.targetFactory,
                intendedCanonicalPointer: intendedPointer)
            pending.phase = .sourceClosed
#if DEBUG
            resumeStage = "postclose-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "target-reader-provider"
#endif
            let exactB = try pending.targetSession.validatedOpeningFactoryForWriter()
#if DEBUG
            resumeStage = "target-coordinator-provider"
#endif
            guard exactB.sharesRegistryProvider(with: pending.targetFactory),
                  try pending.targetCoordinator.requireOriginalEraseOpeningAuthority(
                    factory: exactB) === pending.targetSession else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            generationFactory = exactB
            pending.phase = .rebound
#if DEBUG
            resumeStage = "rebound-coordinator"
#endif
            guard try pending.targetCoordinator.requireOriginalEraseOpeningAuthority(
                    factory: generationFactory) === pending.targetSession else {
                throw AppAccessContractFailureV1.staleAttempt
            }
#if DEBUG
            resumeStage = "rebound-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "target-maintenance-frame"
#endif
            try captureRestoredTargetMaintenanceFrame(pending,
                intendedPointer: intendedPointer)
            pending.phase = .recovering
            let owner = OwnedWriter(pending.targetCoordinator)
            operationOwnedWriter = owner
            let session = pending.targetSession
            let operation = pending.ticket.operationID
#if DEBUG
            resumeStage = "current-generation"
#endif
            guard try generationFactory.currentGenerationID() == session.generationID else {
                throw StartupMaintenanceReason.restoreInconsistent
            }
#if DEBUG
            resumeStage = "generation-leases"
#endif
            try reconcileGenerationLeasesForStartup()
#if DEBUG
            resumeStage = "preparation-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "private-preparations"
#endif
            try await retireCurrentPrivatePreparations(
                session: session, operation: operation, owner: owner)
#if DEBUG
            resumeStage = "finalization-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "finalization-recovery"
#endif
            let finalizationRecovery = FinalizationRecoveryService(
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                workspaceWriter: owner.writer,
                lifecycleProfileRegistry: pending.targetCoordinator.lifecycleProfileRegistry,
                retainedStartupStore: maintenanceFinalizationStore)
            _ = try await finalizationRecovery.reconcile()
            if let store = maintenanceFinalizationStore {
                let receipt = try await store.startupRecoveryJournalReceipt()
                try recordMaintenanceOperationsRecoveryEffect(receipt)
            }
            try await closeMaintenanceFinalizationOwnerChecked()
#if DEBUG
            resumeStage = "deletion-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "whole-sign-recovery"
#endif
            try requireBeforeMaintenanceOperationsEffect()
            let descriptorOwner: RestoreMaintenanceOperationsDescriptorOwnerV1?
            if maintenanceControlFrame != nil {
                descriptorOwner = RestoreMaintenanceOperationsDescriptorOwnerV1()
                maintenanceDeletionDescriptorOwner = descriptorOwner
            } else { descriptorOwner = nil }
            let deletionRecovery = WholeSignDeletionService(
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                fileManager: fileManager,
                trackStartupOperationsCreation: maintenanceControlFrame != nil,
                startupDescriptorOwner: descriptorOwner)
            maintenanceDeletionService = deletionRecovery
            if maintenanceControlFrame != nil {
                try recordMaintenanceOperationsEffect {
                    try descriptorOwner?.requireOpen()
                    return try deletionRecovery.startupOperationsReceipt()
                }
                maintenanceOperationsUncertain = true
            }
            _ = try await deletionRecovery.reconcile()
            if maintenanceControlFrame != nil {
                try recordMaintenanceOperationsRecoveryEffect(
                    deletionRecovery.startupRecoveryJournalReceipt())
            }
            try closeMaintenanceDeletionOwnerChecked()
#if DEBUG
            resumeStage = "media-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "media-recovery"
#endif
            try await recoverCurrentMedia(session: session, operation: operation, owner: owner)
#if DEBUG
            resumeStage = "report-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "report-construction"
#endif
            let recovery = try makeActiveReportRecovery(
                session: session, coordinator: pending.targetCoordinator)
#if DEBUG
            resumeStage = "report-recovery"
#endif
            try recovery.reconcileAtStartup()
#if DEBUG
            resumeStage = "writer-history"
#endif
            _ = try owner.writer.sourceMutationHistorySnapshot()
#if DEBUG
            resumeStage = "diagnostics"
#endif
            await diagnosticsStore.prepare()
#if DEBUG
            resumeStage = "commerce-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "commerce-install"
#endif
            try await installCommerceProcessor(operation: operation, owner: owner)
#if DEBUG
            resumeStage = "publication-pending-proof"
#endif
            try await requirePendingRestore(pending)
#if DEBUG
            resumeStage = "publication-authority"
#endif
            guard generationFactory.sharesRegistryProvider(
                    with: pending.targetFactory),
                  try pending.targetCoordinator.requireOriginalEraseOpeningAuthority(
                    factory: generationFactory) === session,
                  try generationFactory.currentGenerationID() == session.generationID else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            operationOwnedWriter = nil
            publishedWriter = owner
            route = .ready(pending.targetCoordinator, diagnosticsStore, recovery)
            pendingRestoreReaderTransition = nil
            endOperation(operation)
            return true
        } catch {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_RESUME_PHASE_V1 first=\(resumeStage) errorType=\(String(reflecting: type(of: error)))\n".utf8))
#endif
            pending.phase = .uncertain
            route = .maintenance(.restoreInconsistent)
            throw error
        }
    }

    private func activateRestoredSessionCore(
        _ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator?,
        ticket: OriginalOperationTicket?
    ) async throws {
        if let ticket {
            let state = try await validateOriginalOperation(ticket, kind: .restore)
            try await state.authorization.validate()
        }
        guard pendingEraseDrainProof == nil else {
            failClosedErase()
            return
        }
        guard ticket != nil || !isRunning else { return }
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.restoreInconsistent)
            return
        }
        let operation = ticket?.operationID ?? beginOperation(.restored)
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
        guard !maintenanceOperationsUncertain else {
            route = .maintenance(.restoreInconsistent)
            return
        }
        clearMaintenanceFrameForNewOpening()
        var unpublishedOwner: OwnedWriter?

        do {
            // Restore has no equivalent of EraseGenerationDrainProof. Keep all
            // retired generation bytes for the remainder of this process even
            // after the coordinator releases its old session lease.
            retainsGenerationsUntilColdLaunch = true
            let intendedPointer: Data?
            if let ticket {
                guard let attested = originalOperations[
                    ticket.operationID]?.restoreTargetPointerData else {
                    throw AppAccessContractFailureV1.staleAttempt
                }
                intendedPointer = attested
            } else {
                intendedPointer = nil
            }
            try captureMaintenanceFrame(session,
                intendedPointer: intendedPointer)
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
            maintenanceFrameHadInstalledWriter = true

            do {
                try await retireCurrentPrivatePreparations(session: session, operation: operation, owner: owner)
                _ = try await FinalizationRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    workspaceWriter: owner.writer,
                    lifecycleProfileRegistry: activeCoordinator.lifecycleProfileRegistry,
                    retainedStartupStore: maintenanceFinalizationStore
                ).reconcile()
                if let store = maintenanceFinalizationStore {
                    let receipt = try await store.startupRecoveryJournalReceipt()
                    try recordMaintenanceOperationsRecoveryEffect(receipt)
                }
                try await closeMaintenanceFinalizationOwnerChecked()
                try await requireCurrentOperationAndAccess(operation, owner: owner)
                try requireBeforeMaintenanceOperationsEffect()
                let descriptorOwner: RestoreMaintenanceOperationsDescriptorOwnerV1?
                if maintenanceControlFrame != nil {
                    descriptorOwner = RestoreMaintenanceOperationsDescriptorOwnerV1()
                    maintenanceDeletionDescriptorOwner = descriptorOwner
                } else { descriptorOwner = nil }
                let deletionRecovery = WholeSignDeletionService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager,
                    trackStartupOperationsCreation: maintenanceControlFrame != nil,
                    startupDescriptorOwner: descriptorOwner)
                maintenanceDeletionService = deletionRecovery
                if maintenanceControlFrame != nil {
                    try recordMaintenanceOperationsEffect {
                        try descriptorOwner?.requireOpen()
                        return try deletionRecovery.startupOperationsReceipt()
                    }
                    maintenanceOperationsUncertain = true
                }
                _ = try await deletionRecovery.reconcile()
                if maintenanceControlFrame != nil {
                    try recordMaintenanceOperationsRecoveryEffect(
                        deletionRecovery.startupRecoveryJournalReceipt())
                }
                try closeMaintenanceDeletionOwnerChecked()
                try await requireCurrentOperationAndAccess(operation, owner: owner)
                try await recoverCurrentMedia(session: session, operation: operation, owner: owner)
                try await requireCurrentOperationAndAccess(operation, owner: owner)
                let recovery = try makeActiveReportRecovery(
                    session: session,
                    coordinator: activeCoordinator
                )
                try recovery.reconcileAtStartup()
                _ = try activeCoordinator.workspaceWriter.sourceMutationHistorySnapshot()
                await diagnosticsStore.prepare()
                try await requireCurrentOperationAndAccess(operation, owner: owner)
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

    private func currentMediaOwnership(session: StoreGenerationSession,
                                       operation: UUID, owner: OwnedWriter) throws -> StartupMediaOwnershipSnapshotV1 {
#if DEBUG
        let timingStarted = DispatchTime.now().uptimeNanoseconds
        let journalPassesBefore = owner.writer.fullJournalValidationPassCountForTesting
        var observedPhotoRows: Int? = nil
        print("STARTUP_MEDIA_TIMING_V1 step=ownership.enter uptimeNs=\(timingStarted)")
        defer {
            let ended = DispatchTime.now().uptimeNanoseconds
            let passes: String
            if let before = journalPassesBefore,
               let after = owner.writer.fullJournalValidationPassCountForTesting {
                passes = String(after &- before)
            } else { passes = "unavailable" }
            print("STARTUP_MEDIA_TIMING_V1 step=ownership.exit uptimeNs=\(ended) elapsedNs=\(ended &- timingStarted) photoRows=\(observedPhotoRows.map { String($0) } ?? "unobserved") writerJournalPassDelta=\(passes)")
        }
#endif
        try requireCurrentMediaOwnerIdentity(session: session, operation: operation, owner: owner)
        let snapshot = try owner.writer.startupMediaOwnershipInReadScope(
            workspaceID: session.workspaceID, modelContext: session.modelContext)
        try requireCurrentMediaOwnerIdentity(session: session, operation: operation, owner: owner)
#if DEBUG
        observedPhotoRows = snapshot.photos.count
#endif
        return snapshot
    }

    /// Media-only identity checks surround a fresh full journal observation.
    /// Other startup callers retain requireCurrentOwner's history export.
    private func requireCurrentMediaOwnerIdentity(session: StoreGenerationSession,
        operation: UUID, owner: OwnedWriter) throws {
        try requireCurrentOperation(operation)
        guard owner.coordinator.workspaceWriter === owner.writer,
              owner.coordinator.generationID == owner.generationID,
              session.generationID == owner.generationID,
              owner.coordinator.modelContext === session.modelContext,
              try generationFactory.currentGenerationID() == owner.generationID else {
            throw OperationFailure.superseded
        }
    }

    private func retireCurrentPrivatePreparations(session: StoreGenerationSession, operation: UUID,
        owner: OwnedWriter) async throws {
        try await requireCurrentOperationAndAccess(operation, owner: owner)
        let originalAuthorization = operationAuthorization
        let revision = try owner.writer.currentRevision()
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        let authority = StartupPrivatePreparationAuthorityV1(generationRootURL: session.generationRootURL,
            rootIdentity: rootIdentity) {
            try self.requireCurrentOperation(operation, owner: owner)
            guard self.operationOwnedWriter?.writer === owner.writer,
                  self.publishedWriter?.writer !== owner.writer,
                  !session.modelContext.hasChanges,
                  try owner.writer.currentRevision() == revision else {
                throw StartupMaintenanceReason.finalizationInconsistent
            }
        }
        try requireBeforeMaintenanceOperationsEffect()
        let trackMaintenanceOperations = maintenanceControlFrame != nil
        let descriptorOwner: RestoreMaintenanceOperationsDescriptorOwnerV1?
        if trackMaintenanceOperations {
            descriptorOwner = RestoreMaintenanceOperationsDescriptorOwnerV1()
            maintenanceFinalizationDescriptorOwner = descriptorOwner
        } else { descriptorOwner = nil }
        let store = FinalizationIntentStore(generationRootURL: session.generationRootURL,
            expectedGenerationRootIdentity: rootIdentity,
            trackStartupOperationsCreation: trackMaintenanceOperations,
            startupDescriptorOwner: descriptorOwner)
        if trackMaintenanceOperations {
            maintenanceFinalizationStore = store
            try recordMaintenanceOperationsEffect {
                try descriptorOwner?.requireOpen()
                return try store.startupOperationsReceipt()
            }
            maintenanceOperationsUncertain = true
        }
        let prepared = try await store.prepareStartupPrivateRetirement(authority: authority)
#if DEBUG
        try await beforePrivatePreparationCleanupForTesting?(session.modelContext)
#endif
        try await requireCurrentOperationAndAccess(operation, owner: owner)
        let publish = {
            try owner.coordinator.withCheckRunnerPhotoPublication(expectedWriter: owner.writer,
                applicationSupportURL: self.applicationSupportURL) {
                try self.requireCurrentOperation(operation, owner: owner)
                try authority.publish(prepared)
            }
        }
        if let originalAuthorization { try originalAuthorization.withMediaRecovery(publish) }
        else { try publish() }
    }

    private func recoverCurrentMedia(session: StoreGenerationSession, operation: UUID,
                                     owner: OwnedWriter) async throws {
        try await requireCurrentOperationAndAccess(operation)
        let originalAuthorization = operationAuthorization
        let snapshot = try currentMediaOwnership(session: session, operation: operation, owner: owner)
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        let authority = StartupMediaRecoveryAuthorityV1(snapshot: snapshot) {
            guard try self.currentMediaOwnership(session: session, operation: operation, owner: owner) == snapshot else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
        let store = EvidenceBundleStore(generationRootURL: session.generationRootURL, fileManager: fileManager)
#if DEBUG
        let preparationStarted = DispatchTime.now().uptimeNanoseconds
        print("STARTUP_MEDIA_TIMING_V1 step=preparation.request uptimeNs=\(preparationStarted)")
#endif
        let prepared = try await store.prepareStartupRecovery(authority: authority,
            expectedGenerationRootIdentity: rootIdentity)
#if DEBUG
        let preparationEnded = DispatchTime.now().uptimeNanoseconds
        print("STARTUP_MEDIA_TIMING_V1 step=preparation.return uptimeNs=\(preparationEnded) elapsedNs=\(preparationEnded &- preparationStarted)")
#endif
#if DEBUG
        try await beforeCurrentMediaCleanupForTesting?(session.modelContext)
#endif
        try await requireCurrentOperationAndAccess(operation, owner: owner)
        let publish = {
            try owner.coordinator.withCheckRunnerPhotoPublication(expectedWriter: owner.writer,
                applicationSupportURL: self.applicationSupportURL) {
                try self.requireCurrentOperation(operation, owner: owner)
                try authority.publish(prepared)
            }
        }
        if let originalAuthorization { try originalAuthorization.withMediaRecovery(publish) }
        else { try publish() } // Existing unauthenticated test/bootstrap route.
    }

    private func recoverOriginalSource(
        _ authority: StoreMigrationSourceRecoveryAuthorityV1,
        operation: UUID
    ) async throws {
        try await requireCurrentOperationAndAccess(operation)
        let finalization = try FinalizationRecoveryService(sourceRecoveryAuthority: authority)
        _ = try await finalization.reconcile()
        try await requireCurrentOperationAndAccess(operation)
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
        try await requireCurrentOperationAndAccess(operation)
        try ReportRecoveryService.settleOriginalSourcePDFs(authority: authority)
        // Re-enumerate original authorities after all effects. This callback
        // returns no context, writer or service to the aggregate engine.
        try await finalization.verifyOriginalRecoverySettled()
        try await requireCurrentOperationAndAccess(operation)
        try WholeSignDeletionService.verifyOriginalRecoverySettled(authority: authority)
        try await media.verifyOriginalRecoverySettled(authorities: survivingMedia())
        try await requireCurrentOperationAndAccess(operation)
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

    private func installCommerceProcessor(
        operation: UUID,
        owner: OwnedWriter,
        postAdoptionExecution: PostAdoptionExecution? = nil
    ) async throws {
        try await requireCurrentOperationAccessAndContent(
            operation, owner: owner, execution: postAdoptionExecution
        )
        let readCommerceInputs: () throws -> (UUID, EntitlementStore) = {
            let writerID = try owner.writer.currentRevision().writerInstanceID
            let store = try EntitlementStore(
                applicationSupportURL: self.applicationSupportURL,
                fileManager: self.fileManager
            )
            return (writerID, store)
        }
        let inputs: (UUID, EntitlementStore)
        if let postAdoptionExecution {
            inputs = try postAdoptionExecution.contentReadToken.withContentRead(
                for: .startupRecovery, readCommerceInputs
            )
        } else {
            inputs = try readCommerceInputs()
        }
        await beforeCommerceActivation(inputs.0)
        try await requireCurrentOperationAccessAndContent(
            operation, owner: owner, execution: postAdoptionExecution
        )
        stopCommerce()
        let processor = StoreKitTransactionProcessor(
            store: inputs.1,
            runtime: entitlementRuntime
        )
        do {
            try await processor.start()
            try await requireCurrentOperationAccessAndContent(
                operation, owner: owner, execution: postAdoptionExecution
            )
            let publishProcessor: () throws -> Void = {
                try self.requireCurrentPostAdoptionExecution(
                    operation: operation, execution: postAdoptionExecution
                )
                if let postAdoptionExecution {
                    self.willReadPostAdoptionCanonicalContent(postAdoptionExecution.executionID)
                }
                try self.requireCurrentOperation(operation, owner: owner)
                self.entitlementProcessor = processor
            }
            if let postAdoptionExecution {
                try postAdoptionExecution.contentReadToken.withContentRead(
                    for: .startupRecovery, publishProcessor
                )
            } else {
                try publishProcessor()
            }
        } catch {
            processor.stop()
            throw error
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

    private func closeMaintenanceFinalizationOwnerChecked() async throws {
        guard let descriptorOwner = maintenanceFinalizationDescriptorOwner else {
            maintenanceFinalizationStore = nil
            return
        }
        guard let store = maintenanceFinalizationStore else {
            maintenanceOperationsUncertain = true
            throw StartupMaintenanceReason.finalizationInconsistent
        }
        do {
            try descriptorOwner.requireOpen()
            maintenanceOperationsUncertain = true
            try await store.closeStartupOperationsAuthorityChecked()
            maintenanceFinalizationStore = nil
            maintenanceFinalizationDescriptorOwner = nil
            maintenanceOperationsUncertain = false
        } catch {
            maintenanceOperationsUncertain = true
            throw error
        }
    }

    private func closeMaintenanceDeletionOwnerChecked() throws {
        guard let descriptorOwner = maintenanceDeletionDescriptorOwner else {
            maintenanceDeletionService = nil
            return
        }
        guard maintenanceDeletionService != nil else {
            maintenanceOperationsUncertain = true
            throw StartupMaintenanceReason.finalizationInconsistent
        }
        do {
            try descriptorOwner.requireOpen()
            try descriptorOwner.closeAllChecked()
            maintenanceDeletionService = nil
            maintenanceDeletionDescriptorOwner = nil
            maintenanceOperationsUncertain = false
        } catch {
            maintenanceOperationsUncertain = true
            throw error
        }
    }

    private func clearMaintenanceFrameForNewOpening() {
        guard !maintenanceOperationsUncertain else { return }
        maintenanceControlFrame = nil
        maintenanceOperationsExpectedFrame = nil
        maintenanceOperationsOwner = nil
        maintenanceFinalizationStore = nil
        maintenanceFinalizationDescriptorOwner = nil
        maintenanceDeletionService = nil
        maintenanceDeletionDescriptorOwner = nil
        maintenanceFrameSession = nil
        maintenanceFrameReader = nil
        maintenanceFrameOpeningFactory = nil
        maintenanceFrameHadInstalledWriter = false
    }

    /// A has already passed the operation-bound target publication proof and
    /// checked source-reader close. Capture B against that original intended
    /// pointer before B's first private-preparation effect. Keep A's frame and
    /// owner intact until the complete B observation succeeds.
    private func captureRestoredTargetMaintenanceFrame(
        _ pending: PendingRestoreReaderTransition,
        intendedPointer: Data
    ) throws {
        guard pendingRestoreReaderTransition === pending,
              pending.phase == .rebound,
              operationID == pending.ticket.operationID,
              pending.ticket.owner === originalOperationOwner,
              originalOperations[pending.ticket.operationID]?.mint
                === pending.ticket.mint,
              originalOperations[pending.ticket.operationID]?.restoreSourceExit
                === pending.source,
              originalOperations[pending.ticket.operationID]?.restoreTargetPointerData
                == intendedPointer,
              maintenanceClearObservation == nil,
              !maintenanceOperationsUncertain,
              maintenanceFrameHadInstalledWriter,
              maintenanceFinalizationStore == nil,
              maintenanceDeletionService == nil,
              maintenanceFinalizationDescriptorOwner == nil,
              maintenanceDeletionDescriptorOwner == nil,
              let originalFrame = maintenanceControlFrame,
              let originalExpected = maintenanceOperationsExpectedFrame,
              let originalOwner = maintenanceOperationsOwner,
              let originalReader = maintenanceFrameReader,
              let originalOpening = maintenanceFrameOpeningFactory,
              originalFrame.generationID == pending.source.sourceGenerationID,
              originalExpected.generationID == originalFrame.generationID,
              originalReader === pending.source.reader,
              originalOpening.sharesRegistryProvider(with: pending.originalFactory),
              !originalOwner.hasUncertainClose,
              generationFactory.sharesRegistryProvider(with: pending.targetFactory),
              pending.targetCoordinator.workspaceWriter
                === pending.writerOwner.constructedWriterForTransition,
              pending.targetSession.generationID != originalFrame.generationID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let opening = try pending.targetSession.validatedOpeningFactoryForWriter()
        let reader = try pending.targetSession.retainedReaderForOriginalRestoreTransition(
            factory: opening)
        guard opening.sharesRegistryProvider(with: generationFactory),
              reader === pending.targetReader,
              opening.restoreApplicationSupportURL.standardizedFileURL
                == applicationSupportURL.standardizedFileURL else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var root = stat()
        guard Darwin.lstat(applicationSupportURL.standardizedFileURL.path,
                &root) == 0,
              root.st_mode & S_IFMT == S_IFDIR,
              root.st_nlink > 0,
              root.st_dev == originalFrame.support.device,
              root.st_ino == originalFrame.support.inode else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let observation = try opening.makeRestoreMaintenanceClearObservation(
            expectedApplicationSupportIdentity: StoreApplicationSupportIdentity(
                device: root.st_dev, inode: root.st_ino))
        maintenanceClearObservation = observation // retain before first open
        do {
            let frame = try observation.captureFrame(session: pending.targetSession,
                intendedPointer: intendedPointer)
            guard pendingRestoreReaderTransition === pending,
                  pending.phase == .rebound,
                  originalOperations[pending.ticket.operationID]?.restoreTargetPointerData
                    == intendedPointer,
                  frame.generationID == pending.targetSession.generationID,
                  frame.current == intendedPointer,
                  !originalOwner.hasUncertainClose else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            maintenanceControlFrame = frame
            maintenanceOperationsExpectedFrame = frame
            maintenanceOperationsOwner = observation
            maintenanceFrameSession = pending.targetSession
            maintenanceFrameReader = reader
            maintenanceFrameOpeningFactory = opening
            maintenanceFrameHadInstalledWriter = true
            maintenanceClearObservation = nil
        } catch {
            if observation.hasUncertainClose {
                Self.retainedUncertainMaintenanceObservations.append(observation)
            }
            maintenanceClearObservation = nil
            throw error
        }
    }

    /// The opened reader and provider are the authority for this observation.
    /// Capture before Router recovery awaits, and keep the original canonical
    /// controls as a value rather than adopting any later maintenance state.
    private func captureMaintenanceFrame(
        _ session: StoreGenerationSession,
        intendedPointer: Data? = nil
    ) throws {
        guard maintenanceClearObservation == nil,
              maintenanceControlFrame == nil else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let opening = try session.validatedOpeningFactoryForWriter()
        guard opening.sharesRegistryProvider(with: generationFactory) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let reader = try session.retainedReaderForOriginalRestoreTransition(
            factory: opening)
        var root = stat()
        guard Darwin.lstat(applicationSupportURL.standardizedFileURL.path,
                &root) == 0,
              root.st_mode & S_IFMT == S_IFDIR,
              root.st_nlink > 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let observation = try opening.makeRestoreMaintenanceClearObservation(
            expectedApplicationSupportIdentity: StoreApplicationSupportIdentity(
                device: root.st_dev, inode: root.st_ino))
        maintenanceClearObservation = observation
        do {
            let frame = try observation.captureFrame(session: session,
                intendedPointer: intendedPointer)
            maintenanceControlFrame = frame
            maintenanceOperationsExpectedFrame = frame
            maintenanceOperationsOwner = observation
            maintenanceFrameSession = session
            maintenanceFrameReader = reader
            maintenanceFrameOpeningFactory = opening
            maintenanceClearObservation = nil
        } catch {
            if observation.hasUncertainClose {
                Self.retainedUncertainMaintenanceObservations.append(observation)
            } else {
                maintenanceClearObservation = nil
            }
            throw error
        }
    }

    private func requireBeforeMaintenanceOperationsEffect() throws {
        guard !maintenanceOperationsUncertain else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        if maintenanceControlFrame == nil {
            guard maintenanceOperationsExpectedFrame == nil,
                  maintenanceOperationsOwner == nil else {
                maintenanceOperationsUncertain = true
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return
        }
        guard let expected = maintenanceOperationsExpectedFrame,
              let owner = maintenanceOperationsOwner else {
            maintenanceOperationsUncertain = true
            throw StoreGenerationFailure.dataPointerInvalid
        }
        do {
            try owner.requireBeforeOperationsEffect(matching: expected)
        } catch {
            maintenanceOperationsUncertain = true
            throw error
        }
    }

    private func recordMaintenanceOperationsEffect(
        _ receipt: () throws -> RestoreMaintenanceClearObservationV1.OperationsChildReceipt
    ) throws {
        guard let original = maintenanceControlFrame,
              let expected = maintenanceOperationsExpectedFrame,
              let owner = maintenanceOperationsOwner else {
            maintenanceOperationsUncertain = true
            throw StoreGenerationFailure.dataPointerInvalid
        }
        do {
            let authenticated = try receipt()
            maintenanceOperationsExpectedFrame = try owner.recordOperationsEffect(
                original: original, previous: expected, receipt: authenticated)
        } catch {
            maintenanceOperationsUncertain = true
            throw error
        }
    }

    private func recordMaintenanceOperationsRecoveryEffect(
        _ receipt: RestoreMaintenanceClearObservationV1.OperationsRecoveryReceipt
    ) throws {
        guard maintenanceOperationsUncertain,
              let original = maintenanceControlFrame,
              let expected = maintenanceOperationsExpectedFrame,
              let owner = maintenanceOperationsOwner else {
            maintenanceOperationsUncertain = true
            throw StoreGenerationFailure.dataPointerInvalid
        }
        do {
            maintenanceOperationsExpectedFrame = try owner
                .recordOperationsRecoveryEffect(original: original,
                    previous: expected, receipt: receipt)
        } catch {
            maintenanceOperationsUncertain = true
            throw error
        }
    }

    private func requireMaintenanceFrame(
        _ session: StoreGenerationSession,
        validatedImport: ValidatedV4BackupPackageV1? = nil
    ) throws {
        guard !maintenanceOperationsUncertain,
              maintenanceOperationsExpectedFrame != nil,
              maintenanceOperationsOwner != nil,
              maintenanceFinalizationStore == nil,
              maintenanceDeletionService == nil,
              maintenanceFrameHadInstalledWriter,
              maintenanceFrameSession === session,
              let frame = maintenanceControlFrame,
              let opening = maintenanceFrameOpeningFactory,
              let reader = maintenanceFrameReader,
              opening.sharesRegistryProvider(with: generationFactory),
              try session.validatedOpeningFactoryForWriter()
                .sharesRegistryProvider(with: opening),
              try session.retainedReaderForOriginalRestoreTransition(
                factory: opening) === reader,
              reader.token.epoch.generationID == frame.generationID,
              session.generationID == frame.generationID,
              !session.modelContext.hasChanges else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard maintenanceJournalAuthorityIsClear(matching: frame,
                  validatedImport: validatedImport),
              try session.validatedOpeningFactoryForWriter()
                .sharesRegistryProvider(with: opening),
              try session.retainedReaderForOriginalRestoreTransition(
                factory: opening) === reader else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func eligibleMaintenanceRestoreSession(
        _ session: StoreGenerationSession
    ) -> StoreGenerationSession? {
        guard !hasPendingWriterCleanup,
              maintenanceFinalizationStore == nil,
              maintenanceDeletionService == nil else {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_MAINTENANCE_ELIGIBILITY_V1 first=writer-cleanup\n".utf8))
#endif
            return nil
        }
        guard BackupRestoreService.isEmptyCurrent(session.modelContext) else {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_MAINTENANCE_ELIGIBILITY_V1 first=nonempty-source\n".utf8))
#endif
            return nil
        }
        guard (try? requireMaintenanceFrame(session)) != nil else {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_MAINTENANCE_ELIGIBILITY_V1 first=control-frame\n".utf8))
#endif
            return nil
        }
        return session
    }

    private func eligibleMaintenanceEraseSession(
        _ session: StoreGenerationSession
    ) -> StoreGenerationSession? {
        guard !hasPendingWriterCleanup,
              maintenanceFinalizationStore == nil,
              maintenanceDeletionService == nil,
              !session.modelContext.hasChanges,
              (try? requireMaintenanceFrame(session)) != nil else {
            return nil
        }
        // EraseAllService.erase retains its full current/retired, package,
        // receipt, policy and intent validation before its first effect. The
        // option itself uses only this original, no-repair reader frame.
        return session
    }

    private func maintenanceJournalAuthorityIsClear(
        matching frame: RestoreMaintenanceClearObservationV1.Frame,
        validatedImport: ValidatedV4BackupPackageV1? = nil
    ) -> Bool {
        // An ambiguous descriptor close is a one-way refusal for this Router.
        guard maintenanceClearObservation == nil else { return false }
        var stage = "root"
        do {
            // This is Application Support, not a generation root. The report
            // helper requires Data/generations/<UUID> and rejects this path.
            // The retained restore authority below opens this exact named
            // directory no-follow and compares the physical identity.
            var root = stat()
            guard Darwin.lstat(applicationSupportURL.standardizedFileURL.path,
                    &root) == 0,
                  root.st_mode & S_IFMT == S_IFDIR,
                  root.st_nlink > 0 else {
#if DEBUG
                FileHandle.standardError.write(Data(
                    "V23_RESTORE_MAINTENANCE_JOURNAL_V1 first=root\n".utf8))
#endif
                return false
            }
            stage = "authority"
            let observation = try generationFactory.makeRestoreMaintenanceClearObservation(
                expectedApplicationSupportIdentity: StoreApplicationSupportIdentity(
                    device: root.st_dev,
                    inode: root.st_ino
                )
            )
            maintenanceClearObservation = observation
            try observation.requireClear(matching: frame,
                expectedOperations: maintenanceOperationsExpectedFrame,
                validatedImport: validatedImport,
                onStage: { stage = $0 })
            maintenanceClearObservation = nil
            return true
        } catch {
            if let observation = maintenanceClearObservation {
                if observation.hasUncertainClose {
                    Self.retainedUncertainMaintenanceObservations.append(observation)
                }
            }
#if DEBUG
            let label: String
            switch error {
            case RestoreMaintenanceClearObservationV1.EmptyRootFailure.restoreGenerations:
                label = "generation-names-nonempty"
            case RestoreMaintenanceClearObservationV1.EmptyRootFailure.importStaging:
                label = "import-names-nonempty"
            default:
                label = stage
            }
            FileHandle.standardError.write(Data(
                "V23_RESTORE_MAINTENANCE_JOURNAL_V1 first=\(label)\n".utf8))
#endif
            return false
        }
    }

    private func noActiveJournal(at url: URL) -> Bool {
        !fileManager.fileExists(atPath: url.path)
    }
}


/// Exact router operation and original access reference. Neither a Coordinator
/// nor a physical EX handle can mint this value. No caller action closure is
/// accepted by its interface, and configuration authorization remains distinct.
@MainActor
final class TemporalNormalizationOperationAuthorityV1 {
    fileprivate let router: StartupRouter
    fileprivate let operationID: UUID
    fileprivate weak var coordinator: StoreSessionCoordinator?
    fileprivate weak var writer: WorkspaceWriterV1?
    fileprivate weak var sourceContext: ModelContext?
    fileprivate let authorization: StartupRouter.StartupAuthorization
    fileprivate let eraseTicket: StartupRouter.OriginalOperationTicket?
    private var retainedExclusion: StoreTemporalNormalizationExclusionV1?
    private var preparedSource: TemporalNormalizationSourceOwnerV1?
    private var retainedSourceSet: TemporalNormalizationRetainedSourceSetV1?
    private var sourceSetPreparationInProgress = false
    private var sourceSetObservationInProgress = false
    private var active = true
    private let copyLifetime = TemporalNormalizationCopyLifetimeV1()
    var sourceOperationID: UUID { operationID }

    fileprivate init(router: StartupRouter, operationID: UUID,
                     coordinator: StoreSessionCoordinator,
                     authorization: StartupRouter.StartupAuthorization,
                     eraseTicket: StartupRouter.OriginalOperationTicket?) {
        self.router = router; self.operationID = operationID
        self.coordinator = coordinator; writer = coordinator.workspaceWriter
        sourceContext = coordinator.modelContext; self.authorization = authorization
        self.eraseTicket = eraseTicket
    }

    fileprivate func revoke() { active = false; copyLifetime.revoke() }

    func validate() async throws {
        try requireLiveBinding()
        try await authorization.validate()
        try requireLiveBinding()
    }

    fileprivate func requireLiveBinding() throws {
        guard active, let coordinator, let writer, let sourceContext,
              coordinator.workspaceWriter === writer,
              coordinator.modelContext === sourceContext else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireTemporalNormalizationOperation(self)
    }

    /// Original reference is taken before the fixed source owner's G edge.
    /// The owner checks its own exact operation/exclusion/source identity.
    func revalidateSource(_ source: TemporalNormalizationSourceOwnerV1) throws {
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.revalidateUnderOriginalAccess(operation: self, scope: scope)
        }
        try requireLiveBinding()
    }

    func allocatePrivateSourceCopy(_ source: TemporalNormalizationSourceOwnerV1) throws {
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.allocatePrivateCopyUnderOriginalAccess(scope: scope)
        }
        try requireLiveBinding()
    }

    func startPrivateSourceCopy(_ source: TemporalNormalizationSourceOwnerV1) throws {
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.requirePrivateCopyAccess(scope: scope)
            let access = try TemporalNormalizationSourceCopyAccessV1(authorization: authorization,
                lifetime: copyLifetime, source: source)
            try source.startPrivateCopyUnderOriginalAccess(scope: scope, access: access)
        }
        try requireLiveBinding()
    }

    func prepareRetainedSourceSet(maximumReportByteCount: Int) async throws -> TemporalNormalizationRetainedSourceSetV1 {
        guard !sourceSetPreparationInProgress, retainedSourceSet == nil, preparedSource == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        sourceSetPreparationInProgress = true
        defer { sourceSetPreparationInProgress = false }
        let source = try await prepareCurrentSourceForOwnedOperation()
        try await readReportsForSet(source, maximumByteCount: maximumReportByteCount)
        let set = try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            return try source.beginRetainedSourceSet(scope: scope)
        }
        retainedSourceSet = set
        try transferSourceToSet(source, set: set)
        for id in set.retiredGenerationIDs {
            let retired = try await prepareRetiredSourceForOwnedOperation(generationID: id)
            try await readReportsForSet(retired, maximumByteCount: maximumReportByteCount)
            try transferSourceToSet(retired, set: set)
        }
        return set
    }
    private func readReportsForSet(_ source: TemporalNormalizationSourceOwnerV1, maximumByteCount: Int) async throws {
        // Uses the owner's actual read snapshot; no caller-supplied row list.
        let snapshot = try await source.readCanonicalSnapshot()
        for report in snapshot.records.reports.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            _ = try await source.readReportSnapshot(reportID: report.id, maximumByteCount: maximumByteCount)
        }
    }
    private func transferSourceToSet(_ source: TemporalNormalizationSourceOwnerV1,
        set: TemporalNormalizationRetainedSourceSetV1) throws {
        guard retainedSourceSet === set, preparedSource === source else { throw AppAccessContractFailureV1.staleAttempt }
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.transferReadSource(to: set, scope: scope)
        }
    }
    func freshRetainedSourceObservations() async throws -> [TemporalNormalizationRetainedSourceObservationV1] {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress, let set = retainedSourceSet else { throw AppAccessContractFailureV1.staleAttempt }
        sourceSetObservationInProgress = true
        defer { sourceSetObservationInProgress = false }
        try await validate()
        do {
            try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                let access = try TemporalNormalizationSourceSetReadAccessV1(authorization: authorization,
                    lifetime: copyLifetime, sourceSet: set)
                try set.startFreshByteObservation(scope: scope, access: access)
            }
        } catch {
            let launchFailure = error
            do { try await set.joinFreshByteObservationIfRunning() }
            catch { throw TemporalNormalizationSourceBoundaryFailureV1(operationFailure: launchFailure, boundaryFailure: error) }
            throw launchFailure
        }
        try await set.joinFreshByteObservation()
        try await validate()
        return try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
            defer { scope.revoke() }
            return try set.observations(scope: scope)
        }
    }
    /// One fixed owner-selected original, never a supplied classification or
    /// supplied source list. Existing preparation must have retained every source.
    func abandonUncommittedOriginal(mutationID: MutationIDV1) async throws -> OrphanFileCleanupSummary {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress,
              let set = retainedSourceSet else { throw AppAccessContractFailureV1.staleAttempt }
        sourceSetObservationInProgress = true
        defer { sourceSetObservationInProgress = false }
        try await validate()
        try Task.checkCancellation()
        do {
            let access = try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                let read = try set.prepareAbandonmentRead(scope: scope)
                let access = try TemporalNormalizationAbandonmentReadAccessV1(authorization: authorization,
                    lifetime: copyLifetime, sourceSet: set, read: read)
                try set.startAbandonmentRead(scope: scope, access: access)
                return access
            }
            try await set.joinAbandonmentRead()
            try await validate()
            try Task.checkCancellation()
            try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                try set.prepareAbandonmentOriginal(mutationID: mutationID, scope: scope)
                try set.startAbandonmentRead(scope: scope, access: access)
            }
            try await set.joinAbandonmentRead()
            try await validate()
            try Task.checkCancellation()
            try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                try set.finishAbandonmentOriginal(scope: scope)
                let sourceAccess = try TemporalNormalizationSourceSetReadAccessV1(authorization: authorization,
                    lifetime: copyLifetime, sourceSet: set)
                try set.startFreshByteObservation(scope: scope, access: sourceAccess)
            }
            try await set.joinFreshByteObservation()
            try await validate()
            try Task.checkCancellation()
            try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                try set.startAbandonmentClassification(scope: scope)
            }
            try await set.joinAbandonmentClassification()
            try await validate()
            try Task.checkCancellation()
            return try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                return try set.executeOriginalAbandonment(scope: scope)
            }
        } catch {
            let failure = error
            do {
                try await set.joinAbandonmentReadIfRunning()
                try await set.joinFreshByteObservationIfRunning()
                try await set.joinAbandonmentClassificationIfRunning()
            } catch {
                throw TemporalNormalizationSourceBoundaryFailureV1(operationFailure: failure, boundaryFailure: error)
            }
            throw failure
        }
    }
    func closeRetainedSourceSetAfterFailure() throws {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress else { throw AppAccessContractFailureV1.staleAttempt }
        try retainedSourceSet?.closeAfterFailure()
        try retainedSourceSet?.requireClosed()
        retainedSourceSet = nil
    }

    func readReportSnapshot(_ source: TemporalNormalizationSourceOwnerV1, reportID: UUID,
        maximumByteCount: Int) throws -> TemporalNormalizationReportSnapshotObservationV1 {
        try requireLiveBinding()
        return try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            return try source.readReportSnapshotUnderOriginalAccess(reportID: reportID,
                maximumByteCount: maximumByteCount, scope: scope)
        }
    }
    func revalidateReportSnapshot(_ source: TemporalNormalizationSourceOwnerV1,
        observation: TemporalNormalizationReportSnapshotObservationV1) throws {
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.revalidateReportSnapshotUnderOriginalAccess(observation, scope: scope)
        }
    }

    func readPrivateCanonicalSource(_ source: TemporalNormalizationSourceOwnerV1) throws
        -> TemporalNormalizationCanonicalSnapshotV1 {
        try requireLiveBinding()
        return try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            return try source.readCanonicalSnapshotUnderOriginalAccess(scope: scope)
        }
    }

    func prepareCurrentSource() async throws -> TemporalNormalizationSourceOwnerV1 {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress, retainedSourceSet == nil else { throw AppAccessContractFailureV1.staleAttempt }
        sourceSetPreparationInProgress = true
        defer { sourceSetPreparationInProgress = false }
        return try await prepareCurrentSourceForOwnedOperation()
    }
    private func prepareCurrentSourceForOwnedOperation() async throws -> TemporalNormalizationSourceOwnerV1 {
        try await validate()
        guard let coordinator else { throw AppAccessContractFailureV1.staleAttempt }
        let exclusion = try await coordinator.drainTemporalProducersForNormalization()
        retainedExclusion = exclusion
        do {
            try await validate()
            return try authorization.withMediaRecovery {
                try requireLiveBinding()
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourcePreparation(exclusion))
                defer { scope.revoke() }
                let source = try router.makeTemporalNormalizationSource(operation: self, exclusion: exclusion, scope: scope)
                preparedSource = source
                return source
            }
        } catch let preparationFailure {
            // Only actual exclusion disposal is allowed; failure leaves its
            // concrete owner reachable in maintenance for retry, never open.
            do { try exclusion.closeForMaintenance() }
            catch let cleanupFailure {
                throw TemporalNormalizationSourcePreparationFailureV1(
                    preparationFailure: preparationFailure, cleanupFailure: cleanupFailure)
            }
            throw preparationFailure
        }
    }

    func prepareRetiredSource(generationID: UUID) async throws -> TemporalNormalizationSourceOwnerV1 {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress, retainedSourceSet == nil else { throw AppAccessContractFailureV1.staleAttempt }
        sourceSetPreparationInProgress = true
        defer { sourceSetPreparationInProgress = false }
        return try await prepareRetiredSourceForOwnedOperation(generationID: generationID)
    }
    private func prepareRetiredSourceForOwnedOperation(generationID: UUID) async throws -> TemporalNormalizationSourceOwnerV1 {
        try await validate()
        guard let retainedExclusion else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if let preparedSource {
            try preparedSource.requireTerminalDrain(operation: self)
            self.preparedSource = nil
        }
        return try authorization.withMediaRecovery {
            try requireLiveBinding()
            let preparation = TemporalNormalizationOriginalAccessScopeV1(operation: self,
                target: .sourcePreparation(retainedExclusion))
            defer { preparation.revoke() }
            let source = try router.makeRetiredTemporalNormalizationSource(operation: self,
                exclusion: retainedExclusion, generationID: generationID, scope: preparation)
            preparedSource = source // retained before durable reader allocation
            let read = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { read.revoke() }
            try source.allocateRetiredReaderUnderOriginalAccess(scope: read)
            return source
        }
    }

    /// Fixed disposal can be requested after access revocation; it cannot
    /// reopen source reads and does not manufacture completion authority.
    func closePreparedSourceAfterFailure() throws {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress else { throw AppAccessContractFailureV1.staleAttempt }
        try preparedSource?.closePinnedSourceAfterFailure()
        preparedSource = nil
        try closeRetainedSourceSetAfterFailure()
    }

    /// Revokes only this normalization slot. The original Erase content token
    /// remains router-owned for its later exact-subject gate reservation.
    func finishPreparation(source: TemporalNormalizationSourceOwnerV1) throws {
        try requireLiveBinding()
        try source.requireTerminalDrain(operation: self)
        guard preparedSource === source, retainedSourceSet == nil else { throw AppAccessContractFailureV1.staleAttempt }
        preparedSource = nil
        router.finishTemporalNormalizationOperation(self)
    }
}

extension StartupRouter {
    private func beginTemporalNormalizationForStartup(
        coordinator: StoreSessionCoordinator, operation: UUID
    ) throws -> TemporalNormalizationOperationAuthorityV1 {
        try requireCurrentOperation(operation)
        guard temporalNormalizationOperation == nil,
              let authorization = operationAuthorization,
              operationKind == .startup || operationKind == .restored,
              operationOwnedWriter?.coordinator === coordinator,
              operationOwnedWriter?.writer === coordinator.workspaceWriter else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let value = TemporalNormalizationOperationAuthorityV1(router: self,
            operationID: operation, coordinator: coordinator,
            authorization: authorization, eraseTicket: nil)
        temporalNormalizationOperation = value
        return value
    }

    func eraseTemporalNormalizationAuthority(
        _ ticket: OriginalOperationTicket, coordinator: StoreSessionCoordinator
    ) async throws -> TemporalNormalizationOperationAuthorityV1 {
        let state = try await validateOriginalOperation(ticket, kind: .erase)
        guard temporalNormalizationOperation == nil, state.eraseSubject == nil,
              !state.eraseAuthorizationIssued, state.acknowledgedReservation == nil,
              state.source.coordinator === coordinator,
              state.source.modelContext === coordinator.modelContext else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let value = TemporalNormalizationOperationAuthorityV1(router: self,
            operationID: ticket.operationID, coordinator: coordinator,
            authorization: state.authorization, eraseTicket: ticket)
        temporalNormalizationOperation = value
        try value.requireLiveBinding()
        return value
    }

    fileprivate func requireTemporalNormalizationOperation(
        _ value: TemporalNormalizationOperationAuthorityV1
    ) throws {
        guard temporalNormalizationOperation === value, value.router === self else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireCurrentOperation(value.operationID)
        if let ticket = value.eraseTicket {
            guard operationKind == .erase, ticket.owner === originalOperationOwner,
                  let state = originalOperations[ticket.operationID],
                  state.owner === ticket.owner, state.mint === ticket.mint,
                  state.kind == .erase, state.eraseSubject == nil,
                  !state.eraseAuthorizationIssued, state.acknowledgedReservation == nil,
                  state.source.coordinator === value.coordinator,
                  state.source.modelContext === value.sourceContext else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        } else {
            guard operationKind == .startup || operationKind == .restored,
                  operationOwnedWriter?.coordinator === value.coordinator,
                  operationOwnedWriter?.writer === value.writer else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        }
    }

    fileprivate func makeTemporalNormalizationSource(
        operation: TemporalNormalizationOperationAuthorityV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        scope: TemporalNormalizationOriginalAccessScopeV1
    ) throws -> TemporalNormalizationSourceOwnerV1 {
        try requireTemporalNormalizationOperation(operation)
        guard let coordinator = operation.coordinator else { throw AppAccessContractFailureV1.staleAttempt }
        return try generationFactory.makeTemporalNormalizationCurrentSource(
            operation: operation, coordinator: coordinator, exclusion: exclusion, scope: scope)
    }

    fileprivate func makeRetiredTemporalNormalizationSource(operation: TemporalNormalizationOperationAuthorityV1,
        exclusion: StoreTemporalNormalizationExclusionV1, generationID: UUID,
        scope: TemporalNormalizationOriginalAccessScopeV1) throws -> TemporalNormalizationSourceOwnerV1 {
        try requireTemporalNormalizationOperation(operation)
        guard let coordinator = operation.coordinator else { throw AppAccessContractFailureV1.staleAttempt }
        return try generationFactory.makeTemporalNormalizationRetiredSource(operation: operation,
            coordinator: coordinator, exclusion: exclusion, generationID: generationID, scope: scope)
    }

    fileprivate func finishTemporalNormalizationOperation(_ value: TemporalNormalizationOperationAuthorityV1) {
        guard temporalNormalizationOperation === value else { return }
        value.revoke()
        temporalNormalizationOperation = nil
    }
}


/// Ephemeral proof that the Router currently holds the ORIGINAL revocation
/// reference. Only its fixed synchronous Router edges can mint it; it is
/// always revoked before that reference is released and never crosses await.
@MainActor
final class TemporalNormalizationOriginalAccessScopeV1 {
    fileprivate enum Target {
        case sourcePreparation(StoreTemporalNormalizationExclusionV1)
        case coldSourcePreparation(TemporalNormalizationColdExclusionV1)
        case sourceRead(TemporalNormalizationSourceOwnerV1)
        case sourceSet(TemporalNormalizationRetainedSourceSetV1)
    }
    private let operation: TemporalNormalizationSourceOperationV1
    private let target: Target
    private var active = true
    fileprivate init(operation: TemporalNormalizationOperationAuthorityV1, target: Target) {
        self.operation = .coordinated(operation); self.target = target
    }
    fileprivate init(operation: TemporalNormalizationColdOperationAuthorityV1, target: Target) {
        self.operation = .cold(operation); self.target = target
    }
    fileprivate func revoke() { active = false }
    func requirePreparation(operation expected: TemporalNormalizationOperationAuthorityV1,
                            exclusion: StoreTemporalNormalizationExclusionV1) throws {
        guard active, operation.matches(.coordinated(expected)),
              case .sourcePreparation(let bound) = target, bound === exclusion else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try operation.requireLiveBinding()
    }
    func requireSourceRead(operation expected: TemporalNormalizationSourceOperationV1,
                           source: TemporalNormalizationSourceOwnerV1) throws {
        guard active, operation.matches(expected),
              case .sourceRead(let bound) = target, bound === source else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try operation.requireLiveBinding()
    }
    func requireSourceSet(operation expected: TemporalNormalizationSourceOperationV1,
        sourceSet: TemporalNormalizationRetainedSourceSetV1) throws {
        guard active, operation.matches(expected), sourceSet.isBound(to: expected),
              case .sourceSet(let bound) = target, bound === sourceSet else { throw AppAccessContractFailureV1.staleAttempt }
        try operation.requireLiveBinding()
    }
    func requireColdPreparation(operation expected: TemporalNormalizationColdOperationAuthorityV1,
                                exclusion: TemporalNormalizationColdExclusionV1) throws {
        guard active, operation.matches(.cold(expected)),
              case .coldSourcePreparation(let bound) = target, bound === exclusion else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try operation.requireLiveBinding()
    }

}


struct TemporalNormalizationSourcePreparationFailureV1: Error {
    let preparationFailure: any Error
    let cleanupFailure: any Error
}


/// A real Router-operation lifetime usable by the fixed detached copy worker.
/// Revocation waits for at most the current synchronous bounded chunk; it is
/// never interpreted as worker drainage or a source-read completion receipt.
fileprivate final class TemporalNormalizationCopyLifetimeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    fileprivate init() {}
    func revoke() { lock.withLock { active = false } }
    func nextAbandonmentChunk(_ read: TemporalNormalizationAbandonmentReadV1) throws -> Bool {
        try lock.withLock {
            guard active else { throw AppAccessContractFailureV1.staleAttempt }
            return try read.readNextChunkUnderOriginalReference()
        }
    }
    func nextSourceSetChunk(_ read: TemporalNormalizationSourceSetFingerprintV1) throws -> Bool {
        try lock.withLock {
            guard active else { throw AppAccessContractFailureV1.staleAttempt }
            return try read.readNextChunkUnderOriginalReference()
        }
    }
    func nextChunk(_ transfer: TemporalNormalizationSQLiteTransferV1) throws -> Bool {
        try lock.withLock {
            guard active else { throw AppAccessContractFailureV1.staleAttempt }
            return try transfer.copyNextChunkUnderOriginalReference()
        }
    }
}

/// No callback or free FD is accepted. A fixed transfer can read only the
/// original source pins and private destination created by this same owner.
final class TemporalNormalizationSourceCopyAccessV1: @unchecked Sendable {
    private enum Reference: Sendable {
        case content(AppAccessGateV1.ContentReadToken)
        case configuration(AppAccessGateV1.ConfigurationStartupRecoveryToken, UUID)
    }
    private let reference: Reference
    private let lifetime: TemporalNormalizationCopyLifetimeV1
    private let sourceIdentity: ObjectIdentifier
    @MainActor
    fileprivate init(authorization: StartupRouter.StartupAuthorization,
                     lifetime: TemporalNormalizationCopyLifetimeV1,
                     source: TemporalNormalizationSourceOwnerV1) throws {
        switch authorization {
        case .content(_, let token): reference = .content(token)
        case .configuration(let authorization):
            guard let token = authorization.startupRecoveryToken else {
                throw AppAccessContractFailureV1.accessDenied
            }
            reference = .configuration(token, authorization.operationID)
        }
        self.lifetime = lifetime; sourceIdentity = ObjectIdentifier(source)
    }
    func copyNextChunk(_ transfer: TemporalNormalizationSQLiteTransferV1) throws -> Bool {
        guard transfer.sourceOwnerIdentity == sourceIdentity else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        // Gate reference precedes the local operation-lifetime lock. There is
        // no actor hop, G lock, namespace R lock or await within either hold.
        switch reference {
        case .content(let token):
            return try token.withContentRead(for: .startupRecovery) { try lifetime.nextChunk(transfer) }
        case .configuration(let token, let operationID):
            return try token.withStartupRecovery(operationID: operationID) { try lifetime.nextChunk(transfer) }
        }
    }
}


/// Cold startup is a distinct Router route. There is no Coordinator, writer,
/// source ModelContext, or reusable current-session authority in this object.
@MainActor
final class TemporalNormalizationColdOperationAuthorityV1 {
    fileprivate let router: StartupRouter
    fileprivate let operationID: UUID
    private let authorization: StartupRouter.StartupAuthorization
    private var active = true
    private let copyLifetime = TemporalNormalizationCopyLifetimeV1()
    private var preparedSource: TemporalNormalizationSourceOwnerV1?
    private var retainedSourceSet: TemporalNormalizationRetainedSourceSetV1?
    private var sourceSetPreparationInProgress = false
    private var sourceSetObservationInProgress = false
    private var exclusion: TemporalNormalizationColdExclusionV1?
    fileprivate init(router: StartupRouter, operationID: UUID,
                     authorization: StartupRouter.StartupAuthorization) {
        self.router = router; self.operationID = operationID; self.authorization = authorization
    }
    fileprivate func revoke() { active = false; copyLifetime.revoke() }
    fileprivate func requireLiveBinding() throws {
        guard active else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireColdTemporalOperation(self)
    }
    func validate() async throws {
        try requireLiveBinding(); try await authorization.validate(); try requireLiveBinding()
    }
    func retainColdExclusion(_ value: TemporalNormalizationColdExclusionV1,
                             scope: TemporalNormalizationColdAccessScopeV1) throws {
        try scope.requireOperation(self)
        guard exclusion == nil, value.isBound(to: self) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        exclusion = value
    }
    func closeAfterFailure() throws {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress else { throw AppAccessContractFailureV1.staleAttempt }
        try preparedSource?.closePinnedSourceAfterFailure()
        preparedSource = nil
        try closeRetainedSourceSetAfterFailure()
        try exclusion?.closeAfterFailure()
        exclusion = nil
        revoke()
    }
    func prepareExclusion() async throws -> TemporalNormalizationColdExclusionV1 {
        try await validate()
        guard exclusion == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        return try authorization.withMediaRecovery {
            try requireLiveBinding()
            let scope = TemporalNormalizationColdAccessScopeV1(operation: self)
            defer { scope.revoke() }
            let value = try router.acquireColdTemporalExclusion(operation: self, scope: scope)
            return value
        }
    }
    func revalidateSource(_ source: TemporalNormalizationSourceOwnerV1) throws {
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.revalidateUnderOriginalAccess(operation: self, scope: scope)
        }
        try requireLiveBinding()
    }

    func allocatePrivateSourceCopy(_ source: TemporalNormalizationSourceOwnerV1) throws {
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.allocatePrivateCopyUnderOriginalAccess(scope: scope)
        }
        try requireLiveBinding()
    }

    func startPrivateSourceCopy(_ source: TemporalNormalizationSourceOwnerV1) throws {
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.requirePrivateCopyAccess(scope: scope)
            let access = try TemporalNormalizationSourceCopyAccessV1(authorization: authorization,
                lifetime: copyLifetime, source: source)
            try source.startPrivateCopyUnderOriginalAccess(scope: scope, access: access)
        }
        try requireLiveBinding()
    }

    func prepareRetainedSourceSet(maximumReportByteCount: Int) async throws -> TemporalNormalizationRetainedSourceSetV1 {
        guard !sourceSetPreparationInProgress, retainedSourceSet == nil, preparedSource == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        sourceSetPreparationInProgress = true
        defer { sourceSetPreparationInProgress = false }
        let source = try await prepareCurrentSourceForOwnedOperation()
        try await readReportsForSet(source, maximumByteCount: maximumReportByteCount)
        let set = try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            return try source.beginRetainedSourceSet(scope: scope)
        }
        retainedSourceSet = set
        try transferSourceToSet(source, set: set)
        for id in set.retiredGenerationIDs {
            let retired = try await prepareRetiredSourceForOwnedOperation(generationID: id)
            try await readReportsForSet(retired, maximumByteCount: maximumReportByteCount)
            try transferSourceToSet(retired, set: set)
        }
        return set
    }
    private func readReportsForSet(_ source: TemporalNormalizationSourceOwnerV1, maximumByteCount: Int) async throws {
        // Uses the owner's actual read snapshot; no caller-supplied row list.
        let snapshot = try await source.readCanonicalSnapshot()
        for report in snapshot.records.reports.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            _ = try await source.readReportSnapshot(reportID: report.id, maximumByteCount: maximumByteCount)
        }
    }
    private func transferSourceToSet(_ source: TemporalNormalizationSourceOwnerV1,
        set: TemporalNormalizationRetainedSourceSetV1) throws {
        guard retainedSourceSet === set, preparedSource === source else { throw AppAccessContractFailureV1.staleAttempt }
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.transferReadSource(to: set, scope: scope)
        }
    }
    func freshRetainedSourceObservations() async throws -> [TemporalNormalizationRetainedSourceObservationV1] {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress, let set = retainedSourceSet else { throw AppAccessContractFailureV1.staleAttempt }
        sourceSetObservationInProgress = true
        defer { sourceSetObservationInProgress = false }
        try await validate()
        do {
            try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                let access = try TemporalNormalizationSourceSetReadAccessV1(authorization: authorization,
                    lifetime: copyLifetime, sourceSet: set)
                try set.startFreshByteObservation(scope: scope, access: access)
            }
        } catch {
            let launchFailure = error
            do { try await set.joinFreshByteObservationIfRunning() }
            catch { throw TemporalNormalizationSourceBoundaryFailureV1(operationFailure: launchFailure, boundaryFailure: error) }
            throw launchFailure
        }
        try await set.joinFreshByteObservation()
        try await validate()
        return try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
            defer { scope.revoke() }
            return try set.observations(scope: scope)
        }
    }
    /// One fixed owner-selected original, never a supplied classification or
    /// supplied source list. Existing preparation must have retained every source.
    func abandonUncommittedOriginal(mutationID: MutationIDV1) async throws -> OrphanFileCleanupSummary {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress,
              let set = retainedSourceSet else { throw AppAccessContractFailureV1.staleAttempt }
        sourceSetObservationInProgress = true
        defer { sourceSetObservationInProgress = false }
        try await validate()
        try Task.checkCancellation()
        do {
            let access = try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                let read = try set.prepareAbandonmentRead(scope: scope)
                let access = try TemporalNormalizationAbandonmentReadAccessV1(authorization: authorization,
                    lifetime: copyLifetime, sourceSet: set, read: read)
                try set.startAbandonmentRead(scope: scope, access: access)
                return access
            }
            try await set.joinAbandonmentRead()
            try await validate()
            try Task.checkCancellation()
            try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                try set.prepareAbandonmentOriginal(mutationID: mutationID, scope: scope)
                try set.startAbandonmentRead(scope: scope, access: access)
            }
            try await set.joinAbandonmentRead()
            try await validate()
            try Task.checkCancellation()
            try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                try set.finishAbandonmentOriginal(scope: scope)
                let sourceAccess = try TemporalNormalizationSourceSetReadAccessV1(authorization: authorization,
                    lifetime: copyLifetime, sourceSet: set)
                try set.startFreshByteObservation(scope: scope, access: sourceAccess)
            }
            try await set.joinFreshByteObservation()
            try await validate()
            try Task.checkCancellation()
            try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                try set.startAbandonmentClassification(scope: scope)
            }
            try await set.joinAbandonmentClassification()
            try await validate()
            try Task.checkCancellation()
            return try authorization.withMediaRecovery {
                let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceSet(set))
                defer { scope.revoke() }
                return try set.executeOriginalAbandonment(scope: scope)
            }
        } catch {
            let failure = error
            do {
                try await set.joinAbandonmentReadIfRunning()
                try await set.joinFreshByteObservationIfRunning()
                try await set.joinAbandonmentClassificationIfRunning()
            } catch {
                throw TemporalNormalizationSourceBoundaryFailureV1(operationFailure: failure, boundaryFailure: error)
            }
            throw failure
        }
    }
    func closeRetainedSourceSetAfterFailure() throws {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress else { throw AppAccessContractFailureV1.staleAttempt }
        try retainedSourceSet?.closeAfterFailure()
        try retainedSourceSet?.requireClosed()
        retainedSourceSet = nil
    }

    func readReportSnapshot(_ source: TemporalNormalizationSourceOwnerV1, reportID: UUID,
        maximumByteCount: Int) throws -> TemporalNormalizationReportSnapshotObservationV1 {
        try requireLiveBinding()
        return try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            return try source.readReportSnapshotUnderOriginalAccess(reportID: reportID,
                maximumByteCount: maximumByteCount, scope: scope)
        }
    }
    func revalidateReportSnapshot(_ source: TemporalNormalizationSourceOwnerV1,
        observation: TemporalNormalizationReportSnapshotObservationV1) throws {
        try requireLiveBinding()
        try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            try source.revalidateReportSnapshotUnderOriginalAccess(observation, scope: scope)
        }
    }

    func readPrivateCanonicalSource(_ source: TemporalNormalizationSourceOwnerV1) throws
        -> TemporalNormalizationCanonicalSnapshotV1 {
        try requireLiveBinding()
        return try authorization.withMediaRecovery {
            let scope = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { scope.revoke() }
            return try source.readCanonicalSnapshotUnderOriginalAccess(scope: scope)
        }
    }


    func prepareCurrentSource() async throws -> TemporalNormalizationSourceOwnerV1 {
        guard !sourceSetPreparationInProgress, !sourceSetObservationInProgress, retainedSourceSet == nil else { throw AppAccessContractFailureV1.staleAttempt }
        sourceSetPreparationInProgress = true
        defer { sourceSetPreparationInProgress = false }
        return try await prepareCurrentSourceForOwnedOperation()
    }
    private func prepareCurrentSourceForOwnedOperation() async throws -> TemporalNormalizationSourceOwnerV1 {
        try await validate()
        if exclusion == nil { _ = try await prepareExclusion() }
        guard let exclusion, preparedSource == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try await validate()
        return try authorization.withMediaRecovery {
            try requireLiveBinding()
            let preparation = TemporalNormalizationOriginalAccessScopeV1(operation: self,
                target: .coldSourcePreparation(exclusion))
            defer { preparation.revoke() }
            let source = try router.makeColdTemporalNormalizationSource(operation: self,
                exclusion: exclusion, scope: preparation)
            preparedSource = source
            let read = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { read.revoke() }
            try source.allocateColdReaderUnderOriginalAccess(scope: read)
            return source
        }
    }
    private func prepareRetiredSourceForOwnedOperation(generationID: UUID) async throws -> TemporalNormalizationSourceOwnerV1 {
        try await validate()
        guard let exclusion, let retainedSourceSet,
              retainedSourceSet.retiredGenerationIDs.contains(generationID) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let preparedSource {
            try preparedSource.requireTerminalDrain(operation: self)
            self.preparedSource = nil
        }
        return try authorization.withMediaRecovery {
            try requireLiveBinding()
            let preparation = TemporalNormalizationOriginalAccessScopeV1(operation: self,
                target: .coldSourcePreparation(exclusion))
            defer { preparation.revoke() }
            let source = try router.makeColdRetiredTemporalNormalizationSource(operation: self,
                exclusion: exclusion, generationID: generationID, scope: preparation)
            preparedSource = source // before the exact retired reader's durable allocation
            let read = TemporalNormalizationOriginalAccessScopeV1(operation: self, target: .sourceRead(source))
            defer { read.revoke() }
            try source.allocateRetiredReaderUnderOriginalAccess(scope: read)
            return source
        }
    }

}

@MainActor
final class TemporalNormalizationColdAccessScopeV1 {
    private let operation: TemporalNormalizationColdOperationAuthorityV1
    private var active = true
    fileprivate init(operation: TemporalNormalizationColdOperationAuthorityV1) { self.operation = operation }
    fileprivate func revoke() { active = false }
    func requireOperation(_ expected: TemporalNormalizationColdOperationAuthorityV1) throws {
        guard active, operation === expected else { throw AppAccessContractFailureV1.staleAttempt }
        try operation.requireLiveBinding()
    }
}

extension StartupRouter {
    private func beginColdTemporalNormalization(operation: UUID) throws
        -> TemporalNormalizationColdOperationAuthorityV1 {
        try requireCurrentOperation(operation)
        guard temporalNormalizationOperation == nil, temporalColdOperation == nil,
              let authorization = operationAuthorization else { throw AppAccessContractFailureV1.staleAttempt }
        let value = TemporalNormalizationColdOperationAuthorityV1(router: self,
            operationID: operation, authorization: authorization)
        temporalColdOperation = value
        do { try requireColdTemporalOperation(value); return value }
        catch { value.revoke(); temporalColdOperation = nil; throw error }
    }
    fileprivate func requireColdTemporalOperation(_ value: TemporalNormalizationColdOperationAuthorityV1) throws {
        try requireCurrentOperation(value.operationID)
        guard temporalColdOperation === value, value.router === self,
              operationKind == .startup, operationOwnedWriter == nil, publishedWriter == nil,
              preparedStartup == nil, maintenanceRestoreSession == nil, maintenanceEraseSession == nil,
              deferredEraseCoordinator == nil, pendingErasedActivation == nil,
              pendingWriterLeaseReleases.isEmpty, pendingCoordinatorReleases.isEmpty,
              originalOperations.isEmpty, temporalNormalizationOperation == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }
    fileprivate func acquireColdTemporalExclusion(operation: TemporalNormalizationColdOperationAuthorityV1,
        scope: TemporalNormalizationColdAccessScopeV1) throws -> TemporalNormalizationColdExclusionV1 {
        try requireColdTemporalOperation(operation)
        try scope.requireOperation(operation)
        return try TemporalNormalizationColdExclusionV1.acquire(
            applicationSupportURL: applicationSupportURL, operation: operation, scope: scope)
    }
}


/// Minted only at the Router's fixed, genuine Erase retirement edge after
/// source-preparation admission has become terminal. Immutable metadata alone
/// cannot construct this permit; the later consuming edge binds all objects.
@MainActor
final class TemporalNormalizationEraseTransferPermitV1 {
    private let binding: EraseRetirementBindingV1
    private let exclusionIdentity: ObjectIdentifier
    private let drainIdentity: ObjectIdentifier
    private var consumed = false
    fileprivate init(binding: EraseRetirementBindingV1,
        exclusion: StoreTemporalNormalizationExclusionV1, drain: EraseSessionDrainWitnessV1) {
        self.binding = binding; exclusionIdentity = ObjectIdentifier(exclusion)
        drainIdentity = ObjectIdentifier(drain)
    }
    func require(binding expected: EraseRetirementBindingV1,
        exclusion: StoreTemporalNormalizationExclusionV1, drain: EraseSessionDrainWitnessV1) throws {
        guard !consumed, binding == expected, exclusionIdentity == ObjectIdentifier(exclusion),
              drainIdentity == ObjectIdentifier(drain) else { throw AppAccessContractFailureV1.staleAttempt }
    }
    func consume(binding expected: EraseRetirementBindingV1,
        exclusion: StoreTemporalNormalizationExclusionV1, drain: EraseSessionDrainWitnessV1) throws {
        try require(binding: expected, exclusion: exclusion, drain: drain)
        consumed = true
    }
}


@MainActor
enum TemporalNormalizationSourceOperationV1 {
    case coordinated(TemporalNormalizationOperationAuthorityV1)
    case cold(TemporalNormalizationColdOperationAuthorityV1)
    func matches(_ other: Self) -> Bool {
        switch (self, other) {
        case (.coordinated(let a), .coordinated(let b)): return a === b
        case (.cold(let a), .cold(let b)): return a === b
        default: return false
        }
    }
    var sourceOperationID: UUID {
        switch self { case .coordinated(let value): return value.sourceOperationID
        case .cold(let value): return value.operationID }
    }
    func validate() async throws {
        switch self { case .coordinated(let value): try await value.validate()
        case .cold(let value): try await value.validate() }
    }
    func revalidateSource(_ source: TemporalNormalizationSourceOwnerV1) throws {
        switch self { case .coordinated(let value): try value.revalidateSource(source)
        case .cold(let value): try value.revalidateSource(source) }
    }
    func allocatePrivateSourceCopy(_ source: TemporalNormalizationSourceOwnerV1) throws {
        switch self { case .coordinated(let value): try value.allocatePrivateSourceCopy(source)
        case .cold(let value): try value.allocatePrivateSourceCopy(source) }
    }
    func startPrivateSourceCopy(_ source: TemporalNormalizationSourceOwnerV1) throws {
        switch self { case .coordinated(let value): try value.startPrivateSourceCopy(source)
        case .cold(let value): try value.startPrivateSourceCopy(source) }
    }
    func readPrivateCanonicalSource(_ source: TemporalNormalizationSourceOwnerV1) throws -> TemporalNormalizationCanonicalSnapshotV1 {
        switch self { case .coordinated(let value): return try value.readPrivateCanonicalSource(source)
        case .cold(let value): return try value.readPrivateCanonicalSource(source) }
    }
    func readReportSnapshot(_ source: TemporalNormalizationSourceOwnerV1, reportID: UUID,
        maximumByteCount: Int) throws -> TemporalNormalizationReportSnapshotObservationV1 {
        switch self {
        case .coordinated(let value): return try value.readReportSnapshot(source, reportID: reportID, maximumByteCount: maximumByteCount)
        case .cold(let value): return try value.readReportSnapshot(source, reportID: reportID, maximumByteCount: maximumByteCount)
        }
    }
    func revalidateReportSnapshot(_ source: TemporalNormalizationSourceOwnerV1,
        observation: TemporalNormalizationReportSnapshotObservationV1) throws {
        switch self {
        case .coordinated(let value): try value.revalidateReportSnapshot(source, observation: observation)
        case .cold(let value): try value.revalidateReportSnapshot(source, observation: observation)
        }
    }
    fileprivate func requireLiveBinding() throws {
        switch self { case .coordinated(let value): try value.requireLiveBinding()
        case .cold(let value): try value.requireLiveBinding() }
    }
}


extension StartupRouter {
    fileprivate func makeColdTemporalNormalizationSource(operation: TemporalNormalizationColdOperationAuthorityV1,
        exclusion: TemporalNormalizationColdExclusionV1, scope: TemporalNormalizationOriginalAccessScopeV1) throws
        -> TemporalNormalizationSourceOwnerV1 {
        try requireColdTemporalOperation(operation)
        let profiles = try lifecycleProfileRegistry ?? WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        return try generationFactory.makeTemporalNormalizationColdSource(operation: operation,
            exclusion: exclusion, profileRegistry: profiles, scope: scope)
    }
}


/// Original access for fixed read-only source-set fingerprint chunks. It is
/// privately minted inside the actual operation scope; no caller FD or closure.
final class TemporalNormalizationSourceSetReadAccessV1: @unchecked Sendable {
    private enum Reference: Sendable {
        case content(AppAccessGateV1.ContentReadToken)
        case configuration(AppAccessGateV1.ConfigurationStartupRecoveryToken, UUID)
    }
    private let reference: Reference
    private let lifetime: TemporalNormalizationCopyLifetimeV1
    private let sourceSetIdentity: ObjectIdentifier
    @MainActor
    fileprivate init(authorization: StartupRouter.StartupAuthorization,
        lifetime: TemporalNormalizationCopyLifetimeV1, sourceSet: TemporalNormalizationRetainedSourceSetV1) throws {
        switch authorization {
        case .content(_, let token): reference = .content(token)
        case .configuration(let authorization):
            guard let token = authorization.startupRecoveryToken else { throw AppAccessContractFailureV1.accessDenied }
            reference = .configuration(token, authorization.operationID)
        }
        self.lifetime = lifetime; sourceSetIdentity = ObjectIdentifier(sourceSet)
    }
    func readNextChunk(_ read: TemporalNormalizationSourceSetFingerprintV1) throws -> Bool {
        guard read.sourceSetIdentity == sourceSetIdentity else { throw AppAccessContractFailureV1.staleAttempt }
        switch reference {
        case .content(let token):
            return try token.withContentRead(for: .startupRecovery) { try lifetime.nextSourceSetChunk(read) }
        case .configuration(let token, let operationID):
            return try token.withStartupRecovery(operationID: operationID) { try lifetime.nextSourceSetChunk(read) }
        }
    }
}


extension StartupRouter {
    fileprivate func makeColdRetiredTemporalNormalizationSource(operation: TemporalNormalizationColdOperationAuthorityV1,
        exclusion: TemporalNormalizationColdExclusionV1, generationID: UUID,
        scope: TemporalNormalizationOriginalAccessScopeV1) throws -> TemporalNormalizationSourceOwnerV1 {
        try requireColdTemporalOperation(operation)
        let profiles = try lifecycleProfileRegistry ?? WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        return try generationFactory.makeTemporalNormalizationColdRetiredSource(operation: operation,
            exclusion: exclusion, generationID: generationID, profileRegistry: profiles, scope: scope)
    }
}

/// Fixed bounded reads of this operation's retained journal and original. No
/// arbitrary path, descriptor, closure or replacement authorization is accepted.
final class TemporalNormalizationAbandonmentReadAccessV1: @unchecked Sendable {
    private enum Reference: Sendable {
        case content(AppAccessGateV1.ContentReadToken)
        case configuration(AppAccessGateV1.ConfigurationStartupRecoveryToken, UUID)
    }
    private let reference: Reference
    private let lifetime: TemporalNormalizationCopyLifetimeV1
    private let sourceSetIdentity: ObjectIdentifier
    private let readIdentity: ObjectIdentifier
    @MainActor
    fileprivate init(authorization: StartupRouter.StartupAuthorization,
        lifetime: TemporalNormalizationCopyLifetimeV1, sourceSet: TemporalNormalizationRetainedSourceSetV1,
        read: TemporalNormalizationAbandonmentReadV1) throws {
        guard read.sourceSetIdentity == ObjectIdentifier(sourceSet) else { throw AppAccessContractFailureV1.staleAttempt }
        switch authorization {
        case .content(_, let token): reference = .content(token)
        case .configuration(let authorization):
            guard let token = authorization.startupRecoveryToken else { throw AppAccessContractFailureV1.accessDenied }
            reference = .configuration(token, authorization.operationID)
        }
        self.lifetime = lifetime; sourceSetIdentity = ObjectIdentifier(sourceSet); readIdentity = ObjectIdentifier(read)
    }
    func readNextChunk(_ read: TemporalNormalizationAbandonmentReadV1) throws -> Bool {
        guard read.sourceSetIdentity == sourceSetIdentity, ObjectIdentifier(read) == readIdentity else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        switch reference {
        case .content(let token):
            return try token.withContentRead(for: .startupRecovery) { try lifetime.nextAbandonmentChunk(read) }
        case .configuration(let token, let operationID):
            return try token.withStartupRecovery(operationID: operationID) { try lifetime.nextAbandonmentChunk(read) }
        }
    }
}


/// Privately minted by the genuine cold startup edge. Metadata alone cannot
/// construct this authority. It retains no model-bearing aggregate or closure.
@MainActor
final class EraseColdRetirementAuthorityV1 {
    fileprivate weak var router: StartupRouter?
    fileprivate let operationID: UUID
    fileprivate weak var preparation: EraseColdPreparationOperationV1?
    private let binding: EraseRetirementBindingV1
    private let registry: GenerationLeaseRegistryV1
    private let drain: EraseSessionDrainWitnessV1
    private let intentStore: EraseIntentStore
    private let observation: EraseIntentStore.RetirementObservation
    private var acquisition: EraseColdRetirementAcquisitionV1?
    private var admissionClosed = false

    fileprivate init(router: StartupRouter, operationID: UUID,
        preparation: EraseColdPreparationOperationV1,
        binding: EraseRetirementBindingV1, registry: GenerationLeaseRegistryV1,
        drain: EraseSessionDrainWitnessV1, intentStore: EraseIntentStore,
        observation: EraseIntentStore.RetirementObservation) {
        self.router = router; self.operationID = operationID
        self.preparation = preparation; self.binding = binding
        self.registry = registry; self.drain = drain
        self.intentStore = intentStore; self.observation = observation
    }

    fileprivate func requireLiveOperation() throws {
        guard let router, !admissionClosed else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireColdEraseRetirement(self)
    }

    func requireAcquisition(binding: EraseRetirementBindingV1,
        registry: GenerationLeaseRegistryV1, drain: EraseSessionDrainWitnessV1,
        scope: EraseColdRetirementAccessScopeV1) throws {
        try requireLiveOperation()
        try scope.requireOperation(self)
        guard self.binding == binding, self.registry === registry,
              self.drain === drain else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try intentStore.requireRetirementObservation(observation)
    }

    func retainedAcquisition(binding: EraseRetirementBindingV1,
        registry: GenerationLeaseRegistryV1, drain: EraseSessionDrainWitnessV1,
        scope: EraseColdRetirementAccessScopeV1) throws -> EraseColdRetirementAcquisitionV1? {
        try requireAcquisition(binding: binding, registry: registry, drain: drain, scope: scope)
        return acquisition
    }

    func retainAcquisition(_ attempt: EraseColdRetirementAcquisitionV1,
        binding: EraseRetirementBindingV1, registry: GenerationLeaseRegistryV1,
        drain: EraseSessionDrainWitnessV1, scope: EraseColdRetirementAccessScopeV1) throws {
        try requireAcquisition(binding: binding, registry: registry, drain: drain, scope: scope)
        guard acquisition == nil, attempt.matches(binding: binding, registry: registry, drain: drain) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        acquisition = attempt
    }

    fileprivate func acquire() async throws -> EraseRetirementExclusionV1 {
        try requireLiveOperation()
        guard let preparation else { throw AppAccessContractFailureV1.staleAttempt }
        try await preparation.validateRetirementAccess()
        try requireLiveOperation()
        return try preparation.withRetirementAccess {
            let scope = EraseColdRetirementAccessScopeV1(operation: self)
            defer { scope.revoke() }
            return try EraseRetirementExclusionV1.acquireCold(binding: binding,
                registry: registry, drain: drain, authority: self, scope: scope)
        }
    }

    /// Called only by the fixed Router detach edge after it has retained the
    /// exact transferred exclusion in its retirement owner. This is admission
    /// closure, never alias-drain or successful-close proof.
    fileprivate func sealForRetirement(exclusion: EraseRetirementExclusionV1) throws {
        try requireLiveOperation()
        guard let acquisition else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try acquisition.sealForRetirement(exclusion: exclusion)
        admissionClosed = true
    }
}

@MainActor
final class EraseColdRetirementAccessScopeV1 {
    private let operation: EraseColdRetirementAuthorityV1
    private var active = true
    fileprivate init(operation: EraseColdRetirementAuthorityV1) { self.operation = operation }
    fileprivate func revoke() { active = false }
    func requireOperation(_ expected: EraseColdRetirementAuthorityV1) throws {
        guard active, operation === expected else { throw AppAccessContractFailureV1.staleAttempt }
        try operation.requireLiveOperation()
    }
}

extension StartupRouter {
    /// Only the cold reconcile route may call this after preparing the exact
    /// cleanup intent and sealing every genuine transient reader allocation.
    fileprivate func prepareColdEraseRetirement(binding: EraseRetirementBindingV1,
        registry: GenerationLeaseRegistryV1, drain: EraseSessionDrainWitnessV1,
        intentStore: EraseIntentStore, intent: EraseIntentV1) throws -> EraseColdRetirementAuthorityV1 {
        guard let preparation = coldErasePreparation else { throw AppAccessContractFailureV1.staleAttempt }
        try requireColdPreparation(preparation)
        guard binding.operationID == preparation.operationID,
              coldEraseRetirement == nil,
              binding.subject.applicationSupportURL == applicationSupportURL.standardizedFileURL,
              intent.eraseID == binding.subject.eraseID,
              intent.newGenerationID == binding.subject.newGenerationID,
              try generationFactory.makeGenerationLeaseRegistry() === registry else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let observation = try intentStore.captureRetirementObservation(expected: intent)
        let value = EraseColdRetirementAuthorityV1(router: self,
            operationID: binding.operationID, preparation: preparation,
            binding: binding, registry: registry, drain: drain,
            intentStore: intentStore, observation: observation)
        coldEraseRetirement = value
        do { try requireColdEraseRetirement(value); return value }
        catch { coldEraseRetirement = nil; throw error }
    }

    fileprivate func requireColdEraseRetirement(_ value: EraseColdRetirementAuthorityV1) throws {
        guard let preparation = value.preparation else { throw AppAccessContractFailureV1.staleAttempt }
        try requireColdPreparation(preparation)
        guard value.operationID == preparation.operationID,
              coldEraseRetirement === value, value.router === self,
              operationKind == .startup, operationOwnedWriter == nil, publishedWriter == nil,
              preparedStartup == nil, maintenanceRestoreSession == nil, maintenanceEraseSession == nil,
              deferredEraseCoordinator == nil, pendingErasedActivation == nil,
              pendingWriterLeaseReleases.isEmpty, pendingCoordinatorReleases.isEmpty,
              originalOperations.isEmpty, temporalNormalizationOperation == nil,
              temporalColdOperation == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }
}


extension StartupRouter {
    /// Only this fixed edge can mint the one-shot permit consumed by M2's
    /// actual EX transfer. Revoking a source slot without genuine disposal is
    /// not enough: the consuming Coordinator edge independently proves the
    /// registered SourceOwner is gone and every real producer has drained.
    fileprivate func makeEraseRetirementPermit(_ ticket: OriginalOperationTicket,
        coordinator: StoreSessionCoordinator, binding: EraseRetirementBindingV1,
        drain: EraseSessionDrainWitnessV1, exclusion: StoreTemporalNormalizationExclusionV1)
        throws -> TemporalNormalizationEraseTransferPermitV1 {
        let state = try awaitlessValidateEraseTicket(ticket)
        guard temporalNormalizationOperation == nil, temporalColdOperation == nil,
              state.source.coordinator === coordinator,
              state.eraseSubject == binding.subject,
              state.acknowledgedReservation?.subject == binding.subject,
              binding.operationID == ticket.operationID,
              binding.ownerMint == state.mint.eraseBindingID,
              coordinator.generationID == binding.subject.newGenerationID,
              try coordinator.eraseRetirementBinding(subject: binding.subject,
                  operationID: ticket.operationID, ownerMint: state.mint.eraseBindingID) == binding else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return TemporalNormalizationEraseTransferPermitV1(binding: binding,
            exclusion: exclusion, drain: drain)
    }
}

/// One actual fresh construction following this Router's completed retirement.
/// Keeps failed allocations, but only weak references to failed model owners.
@MainActor
final class EraseFreshAdoptionOwnerV1 {
    fileprivate enum Phase: Equatable { case registered, constructing, readerPrepared, unpublished, failed, disposing, disposed, published }
    fileprivate weak var router: StartupRouter?
    fileprivate enum Origin {
        case original(StartupRouter.OriginalOperationTicket)
        case cold(EraseColdPreparationOperationV1)
    }
    private enum ReadScope {
        case content(AppAccessGateV1.ContentReadToken)
        case startup(StartupRouter.StartupAuthorization)
        func withRead<T>(_ body: () throws -> T) throws -> T {
            switch self {
            case .content(let token): return try token.withContentRead(for: .startupRecovery, body)
            case .startup(let authorization): return try authorization.withMediaRecovery(body)
            }
        }
    }
    fileprivate let origin: Origin
    fileprivate let retirement: EraseSessionRetirementV1
    fileprivate let proof: ErasedRegistryRetirementProofV1
    fileprivate private(set) var executionID: UUID
    private var readScope: ReadScope
    fileprivate private(set) var factory: StoreGenerationFactory
    private var inventory = EraseReaderRetirementInventoryV1()
    private var inventoryBound = false
    private var settledFailures: [EraseFreshAdoptionDrainWitnessV1] = []
    private var registry: GenerationLeaseRegistryV1?
    private var readerAllocations: [GenerationLeaseAllocationAttemptV1] = []
    private var writerAllocation: GenerationWriterAllocationAttemptV1?
    private var failureWitness: EraseFreshAdoptionDrainWitnessV1?
    private weak var observedSession: StoreGenerationSession?
    private weak var observedWriter: WorkspaceWriterV1?
    private weak var observedCoordinator: StoreSessionCoordinator?
    fileprivate private(set) var ordinaryFactory: StoreGenerationFactory?
    fileprivate private(set) var readySession: StoreGenerationSession?
    fileprivate private(set) var readyCoordinator: StoreSessionCoordinator?
    fileprivate private(set) var phase: Phase = .registered
    private var constructionFrameActive = false

    fileprivate init(router: StartupRouter, ticket: StartupRouter.OriginalOperationTicket,
        retirement: EraseSessionRetirementV1, proof: ErasedRegistryRetirementProofV1,
        executionID: UUID, token: AppAccessGateV1.ContentReadToken,
        factory: StoreGenerationFactory) {
        self.router = router; self.origin = .original(ticket); self.retirement = retirement
        self.proof = proof; self.executionID = executionID; self.readScope = .content(token)
        self.factory = factory
    }

    fileprivate init(router: StartupRouter, cold: EraseColdPreparationOperationV1,
        retirement: EraseSessionRetirementV1, proof: ErasedRegistryRetirementProofV1,
        executionID: UUID, authorization: StartupRouter.StartupAuthorization,
        factory: StoreGenerationFactory) {
        self.router = router; self.origin = .cold(cold); self.retirement = retirement
        self.proof = proof; self.executionID = executionID
        self.readScope = .startup(authorization); self.factory = factory
    }

    private func requireRegistered() throws {
        guard let router else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireFreshEraseOwner(self)
    }

    private func requireConstructionExecution() throws {
        guard let router else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireFreshEraseConstruction(self)
    }

    func requireReaderInventoryBinding(_ value: EraseReaderRetirementInventoryV1) throws {
        try requireRegistered()
        guard phase == .registered, inventory === value else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func registerReaderRegistry(_ value: GenerationLeaseRegistryV1,
        inventory: EraseReaderRetirementInventoryV1, factory: StoreGenerationFactory) throws {
        try requireRegistered()
        try requireConstructionExecution()
        guard phase == .constructing, constructionFrameActive, self.inventory === inventory,
              self.factory.sharesRegistryProvider(with: factory),
              registry == nil || registry === value else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        registry = value
    }

    func retainReaderAllocation(_ value: GenerationLeaseAllocationAttemptV1,
        inventory: EraseReaderRetirementInventoryV1) throws {
        try requireRegistered()
        try requireConstructionExecution()
        guard phase == .constructing, constructionFrameActive, self.inventory === inventory,
              let registry, value.matches(registry: registry),
              value.generationEpoch == proof.binding.generationEpoch,
              !readerAllocations.contains(where: { $0 === value }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        readerAllocations.append(value)
    }

    func requireReaderAllocation(_ value: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1) throws {
        try requireRegistered()
        try requireConstructionExecution()
        guard phase == .constructing, constructionFrameActive,
              self.registry === registry, readerAllocations.contains(where: { $0 === value }),
              value.matches(registry: registry), value.generationEpoch == proof.binding.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireWriterConstruction(session: StoreGenerationSession,
        factory: StoreGenerationFactory) throws {
        try requireRegistered()
        try requireConstructionExecution()
        guard phase == .constructing, constructionFrameActive,
              observedSession === session, self.factory.sharesRegistryProvider(with: factory),
              session.generationEpoch == proof.binding.generationEpoch,
              session.workspaceIdentity == proof.binding.workspaceIdentity,
              session.generationID == proof.binding.subject.newGenerationID,
              registry != nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
    }

    func requireOrdinaryFactoryView(factory: StoreGenerationFactory,
        inventory: EraseReaderRetirementInventoryV1) throws {
        try requireRegistered()
        try requireConstructionExecution()
        guard phase == .constructing, constructionFrameActive, self.inventory === inventory,
              self.factory.sharesRegistryProvider(with: factory), observedSession != nil,
              writerAllocation == nil, ordinaryFactory == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainWriterAllocation(_ value: GenerationWriterAllocationAttemptV1) throws {
        try requireRegistered()
        try requireConstructionExecution()
        guard phase == .constructing, constructionFrameActive, writerAllocation == nil,
              let registry, value.matches(registry: registry),
              value.generationEpoch == proof.binding.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        writerAllocation = value
    }

    func requireWriterAllocation(_ value: GenerationWriterAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1) throws {
        try requireRegistered()
        try requireConstructionExecution()
        guard phase == .constructing, constructionFrameActive,
              self.registry === registry, writerAllocation === value,
              value.matches(registry: registry), value.generationEpoch == proof.binding.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func observeConstructedWriter(_ writer: WorkspaceWriterV1) throws {
        try requireRegistered()
        try requireConstructionExecution()
        guard phase == .constructing, constructionFrameActive,
              writerAllocation?.allocatedHandle != nil, observedWriter == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        observedWriter = writer
    }

    /// The token's real synchronous read scope covers every constructor effect.
    /// No suspension, callback to user code, or nested token lock occurs here.
    fileprivate func construct(lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1) throws {
        try requireRegistered()
        guard case .original = origin, phase == .registered else { throw AppAccessContractFailureV1.staleAttempt }
        if !inventoryBound {
            try inventory.bindFreshAdoption(owner: self)
            factory = try factory.capturingEraseReaders(in: inventory)
            inventoryBound = true
        }
        do {
            try readScope.withRead {
                try requireRegistered()
                guard let router else { throw AppAccessContractFailureV1.staleAttempt }
                try router.requireFreshEraseConstruction(self)
                phase = .constructing
                constructionFrameActive = true
                defer { constructionFrameActive = false }
                let actualRegistry = try factory.makeGenerationLeaseRegistry()
                try registerReaderRegistry(actualRegistry, inventory: inventory, factory: factory)
                guard try factory.currentGenerationID() == proof.binding.subject.newGenerationID else {
                    throw GenerationLeaseRegistryFailureV1.staleGeneration
                }
                let session = try factory.openOrBootstrapCurrent()
                try inventory.capture(session)
                observedSession = session
                try requireWriterConstruction(session: session, factory: factory)
                let ordinary = try factory.ordinaryViewForEraseFreshWriter(adoption: self)
                ordinaryFactory = ordinary
                let coordinator = try StoreSessionCoordinator.makeForEraseFreshAdoption(
                    session: session, generationFactory: ordinary, adoption: self,
                    lifecycleProfileRegistry: lifecycleProfileRegistry)
                observedCoordinator = coordinator
                try requireRegistered()
                readySession = session
                readyCoordinator = coordinator
                phase = .unpublished
            }
        } catch {
            // A denied token before the construction frame caused no I/O.
            // Keep the same effect-free Factory/owner for a fresh real token.
            if phase == .registered { throw error }
            observedWriter?.invalidate()
            readyCoordinator = nil
            readySession = nil
            writerAllocation?.sealForRetirement()
            for allocation in readerAllocations { allocation.sealForRetirement() }
            phase = .failed
            throw error
        }
    }

    /// Cold startup preserves its incumbent ordering: leased current reader,
    /// draft recovery, then the sole writer. Both constructor stages share
    /// this retained allocation owner and the genuine startup authorization.
    fileprivate func constructColdReader() throws -> StoreGenerationSession {
        try requireRegistered()
        try requireConstructionExecution()
        guard case .cold = origin, phase == .registered else { throw AppAccessContractFailureV1.staleAttempt }
        if !inventoryBound {
            try inventory.bindFreshAdoption(owner: self)
            factory = try factory.capturingEraseReaders(in: inventory)
            inventoryBound = true
        }
        do {
            return try readScope.withRead {
                try requireConstructionExecution()
                phase = .constructing
                constructionFrameActive = true
                defer { constructionFrameActive = false }
                let registry = try factory.makeGenerationLeaseRegistry()
                try registerReaderRegistry(registry, inventory: inventory, factory: factory)
                guard try factory.currentGenerationID() == proof.binding.subject.newGenerationID else {
                    throw GenerationLeaseRegistryFailureV1.staleGeneration
                }
                let session = try factory.openOrBootstrapCurrent()
                try inventory.capture(session)
                observedSession = session
                readySession = session
                phase = .readerPrepared
                return session
            }
        } catch {
            if phase != .registered { markFailedColdConstruction() }
            throw error
        }
    }

    fileprivate func constructColdWriter(session: StoreGenerationSession,
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1) throws -> StoreSessionCoordinator {
        try requireRegistered()
        try requireConstructionExecution()
        guard case .cold = origin, phase == .readerPrepared,
              readySession === session, observedSession === session else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        do {
            return try readScope.withRead {
                try requireConstructionExecution()
                phase = .constructing
                constructionFrameActive = true
                defer { constructionFrameActive = false }
                try requireWriterConstruction(session: session, factory: factory)
                let ordinary = try factory.ordinaryViewForEraseFreshWriter(adoption: self)
                ordinaryFactory = ordinary
                let coordinator = try StoreSessionCoordinator.makeForEraseFreshAdoption(
                    session: session, generationFactory: ordinary, adoption: self,
                    lifecycleProfileRegistry: lifecycleProfileRegistry)
                observedCoordinator = coordinator
                readyCoordinator = coordinator
                try requireConstructionExecution()
                phase = .unpublished
                return coordinator
            }
        } catch {
            markFailedColdConstruction()
            throw error
        }
    }

    fileprivate func markFailedColdConstruction() {
        // The same Router retains this owner through lexical caller unwind.
        // Neither this transition nor invalidation claims a successful close.
        guard case .cold = origin, !constructionFrameActive,
              phase == .constructing || phase == .readerPrepared || phase == .unpublished else { return }
        observedWriter?.invalidate()
        readyCoordinator = nil
        readySession = nil
        writerAllocation?.sealForRetirement()
        readerAllocations.forEach { $0.sealForRetirement() }
        phase = .failed
    }

    fileprivate func authorizeColdContinuation(executionID: UUID,
        authorization: StartupRouter.StartupAuthorization) throws {
        try requireRegistered()
        guard case .cold = origin, !constructionFrameActive,
              phase == .registered || phase == .readerPrepared || phase == .unpublished else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        self.executionID = executionID
        self.readScope = .startup(authorization)
    }

    fileprivate func restartColdAfterSuccessfulDisposal(executionID: UUID,
        authorization: StartupRouter.StartupAuthorization) throws {
        try requireRegistered()
        guard case .cold = origin, phase == .disposed, let witness = failureWitness else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let sameProvider = try factory.ordinaryViewAfterEraseFreshFailure(adoption: self)
        settledFailures.append(witness)
        factory = sameProvider
        inventory = EraseReaderRetirementInventoryV1()
        inventoryBound = false
        failureWitness = nil
        ordinaryFactory = nil
        self.executionID = executionID
        self.readScope = .startup(authorization)
        phase = .registered
    }

    fileprivate func authorizeUnstartedExecution(executionID: UUID,
        token: AppAccessGateV1.ContentReadToken) throws {
        try requireRegistered()
        guard case .original = origin, phase == .registered, !constructionFrameActive,
              registry == nil || !settledFailures.isEmpty,
              readerAllocations.isEmpty, writerAllocation == nil, observedSession == nil,
              observedWriter == nil, observedCoordinator == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        self.executionID = executionID
        self.readScope = .content(token)
    }

    func requireDisposedFactoryView(factory: StoreGenerationFactory,
        inventory: EraseReaderRetirementInventoryV1) throws {
        try requireRegistered()
        guard phase == .disposed, !constructionFrameActive, self.inventory === inventory,
              self.factory.sharesRegistryProvider(with: factory), failureWitness != nil,
              readerAllocations.isEmpty, writerAllocation == nil,
              observedSession == nil, observedWriter == nil, observedCoordinator == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    fileprivate func restartAfterSuccessfulDisposal(executionID: UUID,
        token: AppAccessGateV1.ContentReadToken) throws {
        try requireRegistered()
        guard case .original = origin, phase == .disposed, let witness = failureWitness else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let sameProvider = try factory.ordinaryViewAfterEraseFreshFailure(adoption: self)
        settledFailures.append(witness)
        factory = sameProvider
        inventory = EraseReaderRetirementInventoryV1()
        inventoryBound = false
        failureWitness = nil
        ordinaryFactory = nil
        // This is the SAME actual registry/provider. A new Registry or Factory
        // construction is never used to make a failed allocation disappear.
        self.executionID = executionID
        self.readScope = .content(token)
        phase = .registered
    }

    fileprivate func requireReadyForPublication(session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator, factory: StoreGenerationFactory) throws {
        try requireRegistered()
        guard phase == .unpublished, !constructionFrameActive, readySession === session,
              readyCoordinator === coordinator, observedWriter === coordinator.workspaceWriter,
              let ordinaryFactory, ordinaryFactory.sharesRegistryProvider(with: factory),
              let registry, let writerAllocation, writerAllocation.matches(registry: registry),
              writerAllocation.allocatedHandle != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    fileprivate func consumePublication(session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator, factory: StoreGenerationFactory) throws {
        try requireReadyForPublication(session: session, coordinator: coordinator, factory: factory)
        phase = .published
        readySession = nil
        readyCoordinator = nil
    }

    func requireFailureWitnessRegistration(inventory: EraseReaderRetirementInventoryV1,
        registry: GenerationLeaseRegistryV1,
        writerAllocation: GenerationWriterAllocationAttemptV1?) throws {
        try requireRegistered()
        guard phase == .failed, !constructionFrameActive, self.inventory === inventory,
              self.registry === registry, self.writerAllocation === writerAllocation,
              failureWitness == nil, readySession == nil, readyCoordinator == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireFreshFailureDisposal(witness: EraseFreshAdoptionDrainWitnessV1,
        registry: GenerationLeaseRegistryV1) throws {
        try requireRegistered()
        guard phase == .disposing, !constructionFrameActive,
              self.registry === registry, failureWitness === witness,
              observedSession == nil, observedWriter == nil, observedCoordinator == nil,
              readySession == nil, readyCoordinator == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// Only exact successful closes remove retained attempts. A throw leaves
    /// the same attempt/witness available; it never starts another constructor.
    fileprivate func disposeFailedConstruction() throws {
        try requireRegistered()
        guard phase == .failed || phase == .disposing, !constructionFrameActive,
              let registry else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if failureWitness == nil {
            failureWitness = try inventory.sealForFreshAdoptionFailure(owner: self,
                registry: registry, writerAllocation: writerAllocation)
            phase = .disposing
        }
        guard let witness = failureWitness else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if let allocation = writerAllocation {
            try allocation.closeAfterEraseFreshAdoptionFailure(proof: witness)
            writerAllocation = nil
        }
        while let allocation = readerAllocations.first {
            try allocation.closeAfterEraseFreshAdoptionFailure(proof: witness)
            readerAllocations.removeFirst()
        }
        phase = .disposed
    }
}

extension StartupRouter {
    fileprivate func requireFreshEraseOwner(_ value: EraseFreshAdoptionOwnerV1) throws {
        guard freshEraseAdoption === value, value.router === self,
              value.retirement.ownsProof(value.proof) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        switch value.origin {
        case .original(let ticket):
            guard detachedEraseRetirement === value.retirement,
                  ticket.owner === originalOperationOwner,
                  let state = originalOperations[ticket.operationID], state.kind == .erase,
                  state.owner === ticket.owner, state.mint === ticket.mint,
                  state.eraseSubject == value.proof.binding.subject,
                  state.acknowledgedReservation?.subject == state.eraseSubject,
                  state.postAdoptionStartup else { throw AppAccessContractFailureV1.staleAttempt }
        case .cold(let operation):
            try requireRetainedColdPreparation(operation)
            try operation.requireCompletedRetirement(value.retirement, proof: value.proof)
        }
    }

    fileprivate func requireFreshEraseConstruction(_ value: EraseFreshAdoptionOwnerV1) throws {
        try requireFreshEraseOwner(value)
        switch value.origin {
        case .original(let ticket):
            guard operationID == ticket.operationID, operationKind == .erase, isRunning,
                  originalOperations[ticket.operationID]?.postAdoptionExecutionID == value.executionID else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        case .cold(let owner):
            try requireColdPreparation(owner)
            guard operationID == value.executionID, value.executionID == owner.executionID else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        }
    }
}

#if DEBUG
/// One-use fixture authority minted only after the exact original operation's
/// checked reader/writer/EX/guard exit. It pins that old shell and its
/// immutable pre-handoff source binding; it is not an Erase or writer ticket.
@MainActor
final class V949PostHandoffHostileFixtureWitnessV1 {
    let operation: EraseRouterOperationV1
    let originalService: EraseAllService
    let subject: EraseAllOperationSubjectV1
    let reservation: AppAccessGateV1.EraseAdoptionToken
    let binding: V949OriginalEraseSourceBindingV1
    private var fixtureOwnerStarted = false

    fileprivate init(operation: EraseRouterOperationV1,
        originalService: EraseAllService,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken,
        binding: V949OriginalEraseSourceBindingV1) {
        self.operation = operation
        self.originalService = originalService
        self.subject = subject
        self.reservation = reservation
        self.binding = binding
    }

    func beginFixtureOwner() throws {
        guard !fixtureOwnerStarted, reservation.subject == subject,
              binding.eraseID == subject.eraseID,
              binding.newGenerationID == subject.newGenerationID,
              operation.permitsV949PostHandoffFixtureWitness(self) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        fixtureOwnerStarted = true
    }

    func requireFixtureOwnerStarted() throws {
        guard fixtureOwnerStarted,
              operation.permitsV949PostHandoffFixtureWitness(self) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }
}
#endif

/// Private-minted Router ownership for one original Erase. This contains no
/// strong model owner after the consuming transfer; pending cleanup remains
/// bound to the original ticket even when content execution is revoked.
struct OriginalC05PendingDrainAuthorityV1: Sendable {
    let operationID: UUID
    fileprivate init(operationID: UUID) { self.operationID = operationID }
}

/// These are the only Registry cuts admitted while the original Erase keeps
/// its already acquired normalization EX through target writer installation.
/// The Registry checks the complete locked lease set at every cut.
enum EraseOriginalWriterTransitionStageV1 {
    case beforeTarget
    case oldAndTarget
    case afterOld
}

/// The original auxiliary publication owner will construct this only after
/// checked durable roster readback. There is deliberately no public mint in
/// this prerequisite-only source packet.
@MainActor
final class EraseOriginalAuxiliaryRosterPublicationAdmissionV1 {
    let seal: EraseSchema2OriginalAuxiliaryRosterPublicationSealV1
    let receipt: EraseIntentStore.OriginalAuxiliaryRosterPublicationReceiptV1
    fileprivate init(
        seal: EraseSchema2OriginalAuxiliaryRosterPublicationSealV1,
        receipt: EraseIntentStore.OriginalAuxiliaryRosterPublicationReceiptV1
    ) {
        self.seal = seal
        self.receipt = receipt
    }
}

enum OriginalEraseRetainedPointerStageV1: Equatable {
    case current
    case retired
}

/// A one-use admission minted after the original Store's full roster reproof
/// and before it latches the P→Q or Q→R CAS. It carries no filesystem effect
/// authority on its own; Registry and Store still reprove their held controls
/// inside G before and after the synchronous CAS.
@MainActor
final class OriginalEraseAuxiliaryPhaseCASAdmissionV1 {
    fileprivate weak var operation: EraseRouterOperationV1?
    fileprivate weak var store: EraseIntentStore?
    fileprivate let receipt:
        EraseIntentStore.OriginalAuxiliaryRosterPublicationReceiptV1
    fileprivate let expected: EraseIntentV1
    fileprivate let replacement: EraseIntentV1
    fileprivate var entered = false

    fileprivate init(operation: EraseRouterOperationV1,
        store: EraseIntentStore,
        receipt: EraseIntentStore.OriginalAuxiliaryRosterPublicationReceiptV1,
        expected: EraseIntentV1, replacement: EraseIntentV1) {
        self.operation = operation
        self.store = store
        self.receipt = receipt
        self.expected = expected
        self.replacement = replacement
    }

    fileprivate func begin(operation: EraseRouterOperationV1,
        store: EraseIntentStore, expected: EraseIntentV1,
        replacement: EraseIntentV1) throws {
        guard !entered, self.operation === operation,
              self.store === store, self.expected == expected,
              self.replacement == replacement else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        entered = true
    }
}

/// Creation authority is distinct from an existing-root policy request.
/// Only the original operation can issue it inside its authentic Registry G
/// callback, after immutable-P absence and the complete before image are read.
@MainActor final class OriginalEraseNotificationRootCreationPermitV1 {
    let before: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    private let policyPermit: OriginalEraseNotificationRootPolicyPermitV1
    private let check: @MainActor () throws -> Void
    private weak var operation: EraseRouterOperationV1?
    private weak var store: EraseIntentStore?
    private weak var registry: GenerationLeaseRegistryV1?
    private weak var exclusion: StoreTemporalNormalizationExclusionV1?
    private weak var activity: GenerationTemporalActivityHandleV1?
    private weak var observer: EraseSchema2ColdAuxiliaryFirstObserverV1?
    private var active = true

    fileprivate init(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        before: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        policyPermit: OriginalEraseNotificationRootPolicyPermitV1,
        check: @escaping @MainActor () throws -> Void) {
        self.operation = operation
        self.store = store
        self.registry = registry
        self.exclusion = exclusion
        self.activity = activity
        self.observer = observer
        self.before = before
        self.policyPermit = policyPermit
        self.check = check
    }

    func requireBound(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        before: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot) throws {
        guard self.operation === operation, self.store === store,
              self.registry === registry, self.exclusion === exclusion,
              self.activity === activity, self.observer === observer,
              self.before == before else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireHeld()
    }

    func requireHeld() throws {
        guard active else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try policyPermit.requireHeld()
        try check()
    }

    func poisonOnUncertainEffect() { policyPermit.poisonOnUncertainEffect() }
    fileprivate func revoke() { active = false }
}

/// A private original-owner admission for the synchronous Scratch effect lane.
/// Its snapshots are the operation's retained P and checked Notification cut.
/// They are comparison data; every use also proves the actual lexical G owner.
@MainActor
final class OriginalEraseScratchCleanupInitialAdmissionV1 {
    let operationID: UUID
    let applicationSupportURL: URL
    let observer: EraseSchema2ColdAuxiliaryFirstObserverV1
    let firstSnapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    let notificationAfter: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    let physicalRoster: EraseSchema2ColdAuxiliaryPhysicalRosterV1
    let policyReceipt: OriginalEraseScratchControlPolicyReceiptV1
    // bcc's genuine original capture is strict single-link. A future original
    // pair producer must supply its actual receipt; nil grants no pair role.
    let originalGenericPairs: [OriginalEraseScratchCleanupOriginalAliasPremiseV1]? = nil
    private weak var operation: EraseRouterOperationV1?
    private var scope: OriginalEraseScratchCleanupHeldGScopeV1
    var heldScope: OriginalEraseScratchCleanupHeldGScopeV1 { scope }
    private weak var store: EraseIntentStore?
    private weak var registry: GenerationLeaseRegistryV1?
    private weak var exclusion: StoreTemporalNormalizationExclusionV1?
    private weak var activity: GenerationTemporalActivityHandleV1?

    fileprivate init(operation: EraseRouterOperationV1,
        applicationSupportURL: URL,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        firstSnapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        notificationAfter: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        physicalRoster: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        policyReceipt: OriginalEraseScratchControlPolicyReceiptV1,
        scope: OriginalEraseScratchCleanupHeldGScopeV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1) {
        operationID = operation.operationID
        self.operation = operation
        self.applicationSupportURL = applicationSupportURL
        self.observer = observer
        self.firstSnapshot = firstSnapshot
        self.notificationAfter = notificationAfter
        self.physicalRoster = physicalRoster
        self.policyReceipt = policyReceipt
        self.scope = scope
        self.store = store
        self.registry = registry
        self.exclusion = exclusion
        self.activity = activity
    }

    func requireHeld() throws {
        do {
            guard let operation, let store, let registry,
                  let exclusion, let activity else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireOriginalEraseScratchCleanupAdmission(self)
            try scope.requireHeld(operation: operation, store: store,
                registry: registry, exclusion: exclusion, activity: activity)
            try policyReceipt.requireBound(operation: operation, store: store,
                registry: registry, exclusion: exclusion, activity: activity)
        } catch {
            operation?.failOriginalEraseScratchCleanupEffect()
            throw error
        }
    }

    /// Authenticate a canonical starting source against the COMPLETE retained
    /// original roster before the observer keeps lossless bytes. Historical
    /// wire facts contain nine fields; current owner/group are proved by the
    /// actual selected parent/role-policy witness, including inherited SGID.
    /// Historical ownership fields are not invented or read from Support.
    func requireCanonicalSource(path: String, bytes: Data, fullFact: String) throws {
        do {
            try requireHeld()
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            let current = fullFact.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 2,
                  parts.first == "ScratchDataV1" || parts.first == "ProtectedIngressReceiptsV1",
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  current.count == 11,
                  let tree = physicalRoster.record.trees.first(where: {
                    $0.key == "support/FieldEvidenceOperations"
                  }), tree.state == "present", let nodes = tree.nodes,
                  let node = nodes.first(where: { $0.path == path }),
                  node.kind == "file", let expectedSHA = node.sha256 else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard let operation else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireOriginalEraseScratchCleanupCanonicalSourceOwnership(
                path: path, fullFact: fullFact)
            let wire = [0, 1, 2, 5, 6, 7, 8, 9, 10]
                .map { String(current[$0]) }.joined(separator: "|")
            guard wire == node.fact,
                  StoreMigrationCanonicalJSONV1.sha256(bytes) == expectedSHA else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try requireHeld()
        } catch {
            operation?.failOriginalEraseScratchCleanupEffect()
            throw error
        }
    }

    func requirePublicationRequest(intent: OriginalEraseScratchCleanupPrimitiveIntentV1) throws {
        do {
            try requireHeld()
            guard let operation else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireOriginalEraseScratchCleanupPublicationRequest(intent)
            try requireHeld()
        } catch {
            operation?.failOriginalEraseScratchCleanupEffect()
            throw error
        }
    }

    /// Per-subprimitive owner/request proof. It does not scan the complete
    /// tree and cannot adopt any post-effect facts; physical effect scopes
    /// additionally pin their selected current request/birth and exact delta.
    func requirePrimitiveRequest(
        intent: OriginalEraseScratchCleanupPrimitiveIntentV1,
        outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?
    ) throws {
        do {
            try requireHeld()
            guard let operation else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireOriginalEraseScratchCleanupPrimitiveRequest(
                intent: intent, outcome: outcome)
            try requireHeld()
        } catch {
            operation?.failOriginalEraseScratchCleanupEffect()
            throw error
        }
    }

    /// The catalog is a synchronous read-only resource window. This proves
    /// the retained actual attempt/session association without a tree scan or
    /// invoking the session's held check recursively.
    func requireCatalogFrame(
        attempt: OriginalEraseScratchCleanupAttemptV1,
        session: OriginalEraseScratchCanonicalSourceCatalogSessionV1
    ) throws {
        do {
            try requireHeld()
            guard let operation else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireOriginalEraseScratchCleanupCatalogFrame(
                attempt: attempt, session: session)
            try requireHeld()
        } catch {
            operation?.failOriginalEraseScratchCleanupEffect()
            throw error
        }
    }

    fileprivate func renewCompletedObservationScope(
        _ scope: OriginalEraseScratchCleanupHeldGScopeV1) throws {
        guard let operation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireOriginalEraseScratchCleanupCompletedRenewal(self, scope: scope)
        self.scope = scope
        try requireHeld()
    }

    func poisonOnUncertainCleanup() {
        operation?.failOriginalEraseScratchCleanupEffect()
    }
}

/// Effect permission exists only while the original Registry's real G scope
/// and the Coordinator's retained-parent loan are active. Nested Ledger work
/// reuses this exact frame; no ordinary producer SH or new owner is acquired.
@MainActor
final class OriginalEraseScratchCleanupEffectPermitV1 {
    let operationID: UUID
    private weak var operation: EraseRouterOperationV1?
    private weak var store: EraseIntentStore?
    private weak var registry: GenerationLeaseRegistryV1?
    private weak var exclusion: StoreTemporalNormalizationExclusionV1?
    private weak var activity: GenerationTemporalActivityHandleV1?
    private let admission: OriginalEraseScratchCleanupInitialAdmissionV1
    private let imageOwner: OriginalEraseScratchCleanupImageOwnerV1
    private let support: Int32
    private let caches: Int32
    private let temporary: Int32
    private let operations: Int32
    private var active = true
    private var uncertain = false
    private var attempt: OriginalEraseScratchCleanupAttemptV1?
    private var initialImage: OriginalEraseScratchCleanupImageV1?
    private var currentImage: OriginalEraseScratchCleanupImageV1?
    private var pending: OriginalEraseScratchCleanupPrimitiveIntentV1?
    private var pendingOutcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?
    private var lastSequence: UInt64?
    private var activeCatalog: OriginalEraseScratchCanonicalSourceCatalogSessionV1?
    private var completedCatalog: OriginalEraseScratchCanonicalSourceCatalogSessionV1?

    fileprivate init(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        admission: OriginalEraseScratchCleanupInitialAdmissionV1,
        imageOwner: OriginalEraseScratchCleanupImageOwnerV1,
        support: Int32, caches: Int32, temporary: Int32, operations: Int32) {
        operationID = operation.operationID
        self.operation = operation
        self.store = store
        self.registry = registry
        self.exclusion = exclusion
        self.activity = activity
        self.admission = admission
        self.imageOwner = imageOwner
        self.support = support
        self.caches = caches
        self.temporary = temporary
        self.operations = operations
    }

    /// Association data for the concrete Ledger receipt after lexical release.
    /// This does not re-enable an effect or inspect a numeric descriptor.
    func requireOrigin(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        guard !uncertain, self.operation === operation,
              self.store === store, self.registry === registry,
              self.exclusion === exclusion, self.activity === activity,
              operationID == operation.operationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireOriginalEraseScratchCleanupPermitOrigin(self)
    }

    func requireHeld() throws {
        do {
            guard active, !uncertain, let operation else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireOriginalEraseScratchCleanupPermit(self)
            try admission.requireHeld()
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    func requireInitialImage(_ image: OriginalEraseScratchCleanupImageV1) throws {
        do {
            try requireHeld()
            guard pending == nil, pendingOutcome == nil, activeCatalog == nil,
                  initialImage == nil || initialImage == image,
                  currentImage == nil || currentImage == image else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try imageOwner.requireInitialImage(image, support: support,
                caches: caches, temporary: temporary, operations: operations)
            try requireHeld()
            initialImage = image
            currentImage = image
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    func retainAttempt(_ attempt: OriginalEraseScratchCleanupAttemptV1) throws {
        do {
            try requireHeld()
            guard self.attempt == nil || self.attempt === attempt else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            self.attempt = attempt
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    func requireCanonicalSource(path: String, bytes: Data, fullFact: String) throws {
        do {
            try requireHeld()
            try imageOwner.requireCanonicalSource(path: path, bytes: bytes,
                fullFact: fullFact)
            try requireHeld()
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    func beginCanonicalSourceCatalog(
        attempt: OriginalEraseScratchCleanupAttemptV1
    ) throws -> OriginalEraseScratchCanonicalSourceCatalogSessionV1 {
        do {
            try requireHeld()
            guard self.attempt === attempt,
                  attempt.operationID == operationID,
                  let initialImage, currentImage == initialImage,
                  pending == nil, pendingOutcome == nil,
                  lastSequence == nil, activeCatalog == nil,
                  completedCatalog == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let session = try imageOwner.beginCanonicalSourceCatalog(
                attempt: attempt, support: support, caches: caches,
                temporary: temporary, operations: operations)
            // The Ledger binds this exact session before its first source IO.
            // The session's held check is deliberately not called before that
            // private binding exists.
            activeCatalog = session
            try requireHeld()
            return session
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    fileprivate func requireCatalogFrame(
        attempt: OriginalEraseScratchCleanupAttemptV1,
        session: OriginalEraseScratchCanonicalSourceCatalogSessionV1
    ) throws {
        try requireHeld()
        guard self.attempt === attempt, activeCatalog === session,
              completedCatalog == nil, pending == nil, pendingOutcome == nil,
              initialImage != nil, currentImage == initialImage,
              attempt.operationID == operationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try attempt.requireCanonicalCatalogFrame(session: session)
        try requireHeld()
    }

    func finishCanonicalSourceCatalog(
        _ session: OriginalEraseScratchCanonicalSourceCatalogSessionV1,
        attempt: OriginalEraseScratchCleanupAttemptV1
    ) throws {
        do {
            try requireCatalogFrame(attempt: attempt, session: session)
            try imageOwner.finishCanonicalSourceCatalog(session, attempt: attempt,
                support: support, caches: caches, temporary: temporary,
                operations: operations)
            try session.requireCompleted(attempt: attempt)
            try requireHeld()
            // This is retained sequence DATA after the complete physical and
            // resource proof. It grants no permission and never resets the
            // engine's sequence when namespace effects begin.
            lastSequence = attempt.checkedPrimitiveSequence
            completedCatalog = session
            activeCatalog = nil
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    func willPerform(_ intent: OriginalEraseScratchCleanupPrimitiveIntentV1) throws {
        do {
            try requireHeld()
            guard let attempt, let currentImage,
                  intent.operationID == operationID,
                  intent.attemptID == attempt.attemptID,
                  intent.before == currentImage,
                  pending == nil, pendingOutcome == nil,
                  activeCatalog == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let next = (lastSequence ?? 0).addingReportingOverflow(1)
            guard !next.overflow, intent.sequence == next.partialValue else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            // Retain the actual private engine request before any delegated IO.
            pending = intent
            try imageOwner.willPerform(intent, support: support,
                caches: caches, temporary: temporary, operations: operations)
            try requireHeld()
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    func didPerform(_ outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1)
        throws -> OriginalEraseScratchCleanupPrimitiveReadbackV1 {
        do {
            try requireHeld()
            guard pending === outcome.intent, pendingOutcome == nil,
                  outcome.intent.before == currentImage else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            // An actual outcome remains retained on any failed postproof.
            pendingOutcome = outcome
            let after = try imageOwner.didPerform(outcome, support: support,
                caches: caches, temporary: temporary, operations: operations)
            try requireHeld()
            currentImage = after
            lastSequence = outcome.intent.sequence
            pending = nil
            pendingOutcome = nil
            return OriginalEraseScratchCleanupPrimitiveReadbackV1(
                permit: self, outcome: outcome, after: after)
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    fileprivate func requirePrimitiveRequest(
        intent: OriginalEraseScratchCleanupPrimitiveIntentV1,
        outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?
    ) throws {
        try requireHeld()
        guard pending === intent, pendingOutcome === outcome,
              let attempt, intent.operationID == operationID,
              intent.attemptID == attempt.attemptID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try attempt.requireObservationFrame(intent: intent, outcome: outcome)
        try requireHeld()
    }

    /// Read-only policy observation of the actual current image. The physical
    /// owner privately issues the role scope; it gives no setter/effect power.
    func currentTemporalObservationScope() throws -> OriginalEraseScratchTemporalObservationScopeV1 {
        do {
            try requireHeld()
            let scope = try imageOwner.currentTemporalObservationScope()
            try requireHeld()
            return scope
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    func requirePolicyEffectScope(
        intent: OriginalEraseScratchCleanupPrimitiveIntentV1
    ) throws -> OriginalEraseScratchCleanupPolicyEffectScopeV1 {
        do {
            try requirePrimitiveRequest(intent: intent, outcome: nil)
            guard case .requestPolicy = intent.kind else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let scope = try imageOwner.policyEffectScope(intent: intent)
            try requirePrimitiveRequest(intent: intent, outcome: nil)
            return scope
        } catch {
            poisonOnUncertainCleanup()
            throw error
        }
    }

    fileprivate func requirePublicationRequest(
        _ intent: OriginalEraseScratchCleanupPrimitiveIntentV1) throws {
        try requireHeld()
        guard pending === intent, pendingOutcome == nil, let attempt,
              intent.before == currentImage,
              case .createTemporary(let path, _, let bytes, let sha, let mode, _) = intent.kind,
              mode == 0o600,
              StoreMigrationCanonicalJSONV1.sha256(bytes) == sha,
              try attempt.retainedPublicationIntent(temporaryPath: path) === intent else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try attempt.requireObservationFrame(intent: intent, outcome: nil)
        try requireHeld()
    }

    fileprivate func requireReadback(
        _ outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1,
        after: OriginalEraseScratchCleanupImageV1) throws {
        try requireHeld()
        guard currentImage == after, lastSequence == outcome.intent.sequence,
              pending == nil, pendingOutcome == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    fileprivate func requireFinal(_ receipt: OriginalEraseScratchCleanupReceiptV1) throws {
        try requireHeld()
        guard let initialImage, let currentImage, let attempt,
              receipt.initialImage == initialImage,
              receipt.finalImage == currentImage,
              pending == nil, pendingOutcome == nil, activeCatalog == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try receipt.requireBound(operationID: operationID, attempt: attempt,
            finalImage: currentImage)
        try receipt.requireCheckedSettlement()
        try imageOwner.requireFinal(currentImage, support: support,
            caches: caches, temporary: temporary, operations: operations)
        try requireHeld()
    }

    func poisonOnUncertainCleanup() {
        uncertain = true
        operation?.failOriginalEraseScratchCleanupEffect()
    }

    fileprivate func revoke() { active = false }
}

/// One private whole-image acknowledgement, consumed by the issuing engine.
@MainActor
final class OriginalEraseScratchCleanupPrimitiveReadbackV1 {
    let after: OriginalEraseScratchCleanupImageV1
    private weak var permit: OriginalEraseScratchCleanupEffectPermitV1?
    private let outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1
    private var consumed = false

    fileprivate init(permit: OriginalEraseScratchCleanupEffectPermitV1,
        outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1,
        after: OriginalEraseScratchCleanupImageV1) {
        self.permit = permit
        self.outcome = outcome
        self.after = after
    }

    func requireBound(to outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1) throws {
        do {
            guard !consumed, self.outcome === outcome, let permit else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try permit.requireReadback(outcome, after: after)
            consumed = true
        } catch {
            permit?.poisonOnUncertainCleanup()
            throw error
        }
    }
}

@MainActor
final class EraseRouterOperationV1 {
#if DEBUG
    var originalAuxiliaryFixedStageForTesting:
        (@MainActor (String) -> Void)?

    private func traceOriginalAuxiliaryFixedStageForTesting(
        _ stage: String
    ) {
        originalAuxiliaryFixedStageForTesting?(stage)
    }
#endif
    fileprivate weak var router: StartupRouter?
    fileprivate let ticket: StartupRouter.OriginalOperationTicket
    let inventory: EraseReaderRetirementInventoryV1
    var operationID: UUID { ticket.operationID }
    private var binding: EraseRetirementBindingV1?
    private var prepared: EraseCleanupAfterRetirementV1?
    private var drain: EraseSessionDrainWitnessV1?
    private var originalExclusion: StoreTemporalNormalizationExclusionV1?
    private var transferredExclusion: EraseRetirementExclusionV1?
    private var originalAuxiliaryFirstCaptureAttempted = false
    private var originalAuxiliaryFirstObserver:
        EraseSchema2ColdAuxiliaryFirstObserverV1?
    private var originalAuxiliaryFirstCaptureOwner:
        StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1?
    private var originalAuxiliaryFirstSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private enum OriginalTargetReaderStartingImage {
        case originalP(EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot)
        case retainedRecovery(OriginalRecoveryPostPointerAuxiliaryProjectionV1,
            StoreOriginalEraseRecoveryPreOpenOwnerV1)
    }
    private var originalTargetReaderStartingImage:
        OriginalTargetReaderStartingImage?
    private var originalAuxiliaryFirstIntent: EraseIntentV1?
    private var originalAuxiliaryFirstPreparation: ErasePreparationV2?
    private var originalAuxiliaryStore: EraseIntentStore?
    private var originalAuxiliaryRosterCaptureAttempted = false
    private var originalAuxiliaryRosterCapture:
        EraseSchema2OriginalAuxiliaryRosterCaptureV1?
    private var originalAuxiliaryFirstPhysicalRoster:
        EraseSchema2ColdAuxiliaryPhysicalRosterV1?
    private var originalAuxiliaryRosterSealAttempted = false
    private var originalAuxiliaryRosterSeal:
        EraseSchema2OriginalAuxiliaryRosterPublicationSealV1?
    private var originalAuxiliaryRosterAdmission:
        EraseOriginalAuxiliaryRosterPublicationAdmissionV1?
    private var originalAuxiliaryProjectedIntent: EraseIntentV1?
    private var originalAuxiliaryFirstLeaseCensus: [GenerationLeaseTokenV1]?
    private var originalAuxiliaryPhaseCASInFlight = false
    private var originalAuxiliaryPhaseCASUncertain = false
    private var originalAuxiliaryRegistryObservations:
        [EraseSchema2ColdRegistryObservationAttemptV1] = []
    private enum OriginalAuxiliaryRegistryObservationScope: Equatable {
        case preFirstReaderRecordProbe
        case firstRosterCensus
        case writerTransition
        case postPointerReproof
    }
    private var originalAuxiliaryRegistryObservationScope:
        OriginalAuxiliaryRegistryObservationScope?
    private var originalAuxiliaryRegistryObservationFailed = false
    private var originalPostPointerReproofInFlight = false
    private var originalPostPointerReproofUncertain = false
    private var originalAuxiliarySearchWriter:
        OriginalEraseAuxiliarySearchWriterV1?
    private var originalAuxiliarySearchInFlight = false
    private var originalAuxiliarySearchUncertain = false
    private var originalAuxiliarySearchPublished = false
    private var originalAuxiliaryScratchNoRepairAttempted = false
    private var originalAuxiliaryScratchNoRepairInFlight = false
    private var originalAuxiliaryScratchNoRepairUncertain = false
    private var originalAuxiliaryNotificationInFlight = false
    private var originalAuxiliaryNotificationUncertain = false
    private var originalAuxiliaryNotificationBefore:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var originalAuxiliaryNotificationAfter:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var originalAuxiliaryNotificationReceipt:
        OriginalEraseNotificationEffectReceiptV1?
    private var originalAuxiliaryNotificationControl:
        AppLockNotificationControlStoreV1?
    private var originalNotificationPreparedControl:
        AppLockNotificationControlStoreV1?
    private var originalNotificationRootCreationInFlight = false
    private var originalNotificationRootCreationReceipt:
        OriginalEraseNotificationRootCreationReceiptV1?
    private var originalNotificationRootPolicyInFlight = false
    private var originalNotificationRootPolicyUncertain = false
    private var originalNotificationRootPolicyIO:
        EraseAbortCheckedSnapshotIOV1?
    private var originalNotificationRootPolicyBefore:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var originalNotificationRootPolicyAfter:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var originalNotificationRootPolicyReceipt:
        OriginalEraseNotificationRootPolicyReceiptV1?
    private var originalNotificationMarkerInFlight = false
    private var originalNotificationMarkerUncertain = false
    private var originalNotificationMarkerIO:
        EraseAbortCheckedSnapshotIOV1?
    private var originalNotificationMarkerOutsideDigest: String?
    private var originalNotificationMarkerReceipt:
        OriginalEraseNotificationMarkerPublicationReceiptV1?
    private var originalNotificationRemovalInFlight = false
    private var originalNotificationRemovalUncertain = false
    private var originalNotificationRemovalIO:
        EraseAbortCheckedSnapshotIOV1?
    private var originalNotificationOSAbsence:
        OriginalEraseNotificationOSAbsenceReceiptV1?
    private var originalNotificationRemovalReceipt:
        OriginalEraseNotificationRecordRemovalReceiptV1?
    private var originalAuxiliaryScratchControlPolicyInFlight = false
    private var originalAuxiliaryScratchControlPolicyUncertain = false
    private var originalAuxiliaryScratchControlPolicyIO:
        EraseAbortCheckedSnapshotIOV1?
    private var originalAuxiliaryScratchControlPolicyReceipt:
        OriginalEraseScratchControlPolicyReceiptV1?
    private var originalScratchCleanupInFlight = false
    private var originalScratchCleanupUncertain = false
    private var originalScratchCleanupIO: EraseAbortCheckedSnapshotIOV1?
    private var originalScratchCleanupEngineIO: EraseAbortCheckedSnapshotIOV1?
    private var originalScratchCleanupActivity: GenerationTemporalActivityHandleV1?
    private var originalScratchCleanupAdmission: OriginalEraseScratchCleanupInitialAdmissionV1?
    private var originalScratchCleanupImageOwner: OriginalEraseScratchCleanupImageOwnerV1?
    private var originalScratchCleanupPermit: OriginalEraseScratchCleanupEffectPermitV1?
    private var originalScratchCleanupScope: OriginalEraseScratchCleanupHeldGScopeV1?
    private var originalScratchCleanupReceipt: OriginalEraseScratchCleanupReceiptV1?
    private var originalPointerMutationInFlight: OriginalEraseRetainedPointerStageV1?
    private var originalPointerMutationUncertain = false
    private var originalPointerPublished = false
    private var originalRetiredPublished = false
    private var originalCurrentPointerReceipt:
        StoreRestoreGenerationAuthority.OriginalErasePointerReceiptV1?
    private var originalRetiredPointerReceipt:
        StoreRestoreGenerationAuthority.OriginalErasePointerReceiptV1?
    private var originalPointerAuthority: StoreRestoreGenerationAuthority?
    private var originalTargetReaderAllocation:
        GenerationLeaseAllocationAttemptV1?
    private var originalTargetReaderHandle: GenerationLeaseHandleV1?
    private var originalTargetReaderProjection:
        OriginalEraseRetainedTargetReaderProjectionV1?
    private var originalTargetReaderProjectedSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var originalWriterPublicationProjection:
        OriginalEraseRetainedWriterPublicationProjectionV1?
    private var originalWriterProjectedSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var originalWriterProjectionUncertain = false
    private var originalWriterRecoveryInFlight = false
    private var originalWriterRecoveryUncertain = false
    private var originalWriterRecoveryCompleted = false
    private var originalOldWriterReleaseProjection:
        OriginalEraseRetainedOldWriterReleaseProjectionV1?
    private var originalOldWriterProjectedSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var originalOldWriterProjectionUncertain = false
    private var originalTargetReaderInFlight = false
    private var originalTargetReaderUncertain = false
    private var originalTargetReaderFactory: StoreGenerationFactory?
    private var originalTargetReaderAuthority:
        StoreRestoreGenerationAuthority?
    private var originalTargetReaderExpectedPointerData: Data?
    private struct OriginalWriterTransition {
        let registry: GenerationLeaseRegistryV1
        let activity: GenerationTemporalActivityHandleV1
        let oldWriter: GenerationLeaseHandleV1
        let targetAllocation: GenerationWriterAllocationAttemptV1
        let prior: [GenerationLeaseTokenV1]
        var targetPublicationStarted: Bool
        var oldCloseStarted: Bool
        var projected: Bool
    }
    private var originalWriterTransition: OriginalWriterTransition?
    /// Retains the same coordinator-bound actor through every original Erase
    /// suspension and post-detach failure. This is not a cold authority.
    private var originalC05Runner: ResumableLocalJobRunnerV1?
    private var originalC05AbsentStoreObserver: LocalJobStoreV1?
    // The original retry owns each physical no-repair reader before its first
    // open. A failed open or close permanently denies another classification
    // on this operation; an exact V3 refusal retains its open reader.
    private var originalC05NoRepairReaders: [EraseC05ColdPreparationJournalReaderV1] = []
    private var originalC05NoRepairReaderOpen = false
    private var originalC05NoRepairReaderUncertain = false
    private var startedExclusionAcquisition = false
    private var detaching = false
    private(set) var retirement: EraseSessionRetirementV1?
    private(set) var detached = false
#if DEBUG
    private var v949PostHandoffSource: (
        service: EraseAllService,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken,
        binding: V949OriginalEraseSourceBindingV1)?
    private var v949PostHandoffWitnessTaken = false

    fileprivate func armV949PostHandoffSource(
        service: EraseAllService,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken,
        binding: V949OriginalEraseSourceBindingV1
    ) throws {
        guard originalShutdownState == .active,
              v949PostHandoffSource == nil,
              !v949PostHandoffWitnessTaken,
              reservation.subject == subject,
              binding.eraseID == subject.eraseID,
              binding.newGenerationID == subject.newGenerationID,
              binding.oldGenerationID != binding.newGenerationID else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        v949PostHandoffSource = (service, subject, reservation, binding)
    }

    /// Only the original Router calls this after actual Registry G and
    /// physical-root EX acquisition, before releasing its strong model owner.
    fileprivate func beginV949OwnedSourceCloseTransition() throws {
        guard let armed = v949PostHandoffSource else { return }
        guard originalShutdownState == .poisoned,
              originalShutdownActivity != nil, originalShutdownRoot != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try armed.service.beginV949OwnedSourceCloseTransitionForTesting(
            armed.binding, operation: self)
    }

    fileprivate func takeV949PostHandoffWitness()
        throws -> V949PostHandoffHostileFixtureWitnessV1 {
        guard originalShutdownState == .controlsReleased,
              !v949PostHandoffWitnessTaken,
              let armed = v949PostHandoffSource else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        v949PostHandoffWitnessTaken = true
        return V949PostHandoffHostileFixtureWitnessV1(
            operation: self, originalService: armed.service,
            subject: armed.subject, reservation: armed.reservation,
            binding: armed.binding)
    }

    fileprivate func permitsV949PostHandoffFixtureWitness(
        _ value: V949PostHandoffHostileFixtureWitnessV1
    ) -> Bool {
        guard originalShutdownState == .controlsReleased,
              v949PostHandoffWitnessTaken,
              let armed = v949PostHandoffSource else { return false }
        return value.operation === self
            && value.originalService === armed.service
            && value.subject == armed.subject
            && value.reservation == armed.reservation
            && value.binding.eraseID == armed.binding.eraseID
            && value.binding.sourceTreeDigest
                == armed.binding.sourceTreeDigest
    }

    private enum ColdRestartAbandonment { case active, pending, abandoned, closeUncertain }
    private var coldRestartAbandonment = ColdRestartAbandonment.active
    private var wasAttachedToAppAccessForTesting = false
    private weak var attachedAppAccessForTesting: AppAccessPresentationV1?
    func attachAppAccessForTesting(_ owner: AppAccessPresentationV1) throws {
        guard !wasAttachedToAppAccessForTesting, !detached, router != nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try owner.requireOriginalEraseOperationAttachmentForTesting(self)
        wasAttachedToAppAccessForTesting = true
        attachedAppAccessForTesting = owner
    }

    fileprivate func requirePostRetiredAppAccessFenceForTesting(
        originalService: EraseAllService
    ) throws {
        guard wasAttachedToAppAccessForTesting else { return }
        guard let owner = attachedAppAccessForTesting else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try owner.requirePostRetiredOriginalEraseFenceForTesting(
            operation: self, originalService: originalService)
    }
    fileprivate var permitsOriginalEffectForTesting: Bool {
        coldRestartAbandonment == .active && originalShutdownState == .active
    }
    fileprivate var permitsCompletedAbortInventoryBindingForTesting: Bool {
        coldRestartAbandonment == .active && originalShutdownState == .poisoned
    }
#endif

    fileprivate init(router: StartupRouter, ticket: StartupRouter.OriginalOperationTicket,
        inventory: EraseReaderRetirementInventoryV1) {
        self.router = router; self.ticket = ticket; self.inventory = inventory
    }

    private enum PreparationWriterPhase { case absent, constructing, installing, installed }
    private var preparationWriterPhase = PreparationWriterPhase.absent
    private weak var preparationCoordinator: StoreSessionCoordinator?
    private var preparationSourceWriter: GenerationLeaseHandleV1?
    private var preparationFactory: StoreGenerationFactory?
    private var preparationRegistry: GenerationLeaseRegistryV1?
    private var originalRecoveryPreOpenOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1?
    private var originalRecoveryAuxiliaryContinuity:
        StoreOriginalEraseRecoveryAuxiliaryContinuityV1?
    private var originalRecoveryAuxiliaryFirstMatchesOriginalP = false
    private var originalRecoveryPostPointerAuxiliaryProjection:
        OriginalRecoveryPostPointerAuxiliaryProjectionV1?
    private var originalRecoveryPostPointerOwner:
        StoreOriginalEraseRecoveryPreOpenOwnerV1?
    private var originalRecoveryObservation: EraseIntentStore.OriginalRecoveryObservation?
    private var originalRetiredCommitmentInFlight = false
    private var originalRetiredCommitmentUncertain = false
    private var originalRetiredCommitmentReceipt:
        EraseIntentStore.OriginalRecoveryRetiredCommitmentReceiptV1?
    private var originalRetiredStageIdentityInFlight = false
    private var originalRetiredStageIdentityUncertain = false
    private var originalRetiredStageIdentityPublished = false
    private var preparationServiceFrame = false
    private var preparationWriterAllocation: GenerationWriterAllocationAttemptV1?
    private weak var preparationTargetSession: StoreGenerationSession?
    private var preparationTargetRootURL: URL?
    private weak var preparationTargetWriter: WorkspaceWriterV1?
    private var preparationFailureWitness: ErasePreparationFailureDrainWitnessV1?
#if DEBUG
    private enum OriginalShutdownState { case active, poisoned, controlsTransferred, controlsReleased, uncertain }
    private var originalShutdownState = OriginalShutdownState.active
    // True only while the exact poisoned operation synchronously binds its
    // already-disposed preparation witness into the original-reader census.
    private var completedAbortInventoryBindingInProgress = false
    private var originalShutdownWitness: EraseOriginalShutdownWitnessV1?
    private var originalShutdownRegistry: GenerationLeaseRegistryV1?
    private var originalShutdownActivity: GenerationTemporalActivityHandleV1?
    private var originalShutdownRoot: StoreTemporalPhysicalRootExclusionV1?
    private var originalShutdownUncertainActivities: [GenerationTemporalActivityHandleV1] = []
    private var originalShutdownUncertainRoots: [StoreTemporalPhysicalRootExclusionV1] = []
    private var originalShutdownCurrentWriter: GenerationLeaseHandleV1?
    private var originalShutdownInstalled = false
    private var originalShutdownSourceGenerationID: UUID?
    private var originalShutdownTargetGenerationID: UUID?
#endif

    func requirePreparationInventoryBinding(_ value: EraseReaderRetirementInventoryV1) throws {
        guard let router, value === inventory, !detached, prepared == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireEraseRetirementOperation(self)
    }

    func retainPreparationSourceWriter(_ handle: GenerationLeaseHandleV1,
        coordinator: StoreSessionCoordinator) throws -> UUID {
        guard let router, preparationSourceWriter == nil, preparationCoordinator == nil,
              !preparationServiceFrame, preparationFactory == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireLiveEraseService(self, coordinator: coordinator)
        guard handle.token.role == .writer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        preparationSourceWriter = handle
        preparationCoordinator = coordinator
        return ticket.operationID
    }

    fileprivate func configurePreparation(factory: StoreGenerationFactory) throws {
        guard let router, !detached, prepared == nil, !preparationServiceFrame,
              preparationFailureWitness == nil, preparationSourceWriter != nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireEraseRetirementOperation(self)
        if let previous = preparationFactory {
            guard previous.sharesRegistryProvider(with: factory) else { throw AppAccessContractFailureV1.staleAttempt }
        } else { preparationFactory = factory }
    }

    func beginPreparationServiceFrame(coordinator: StoreSessionCoordinator) throws {
        guard let router, preparationCoordinator === coordinator, preparationFactory != nil,
              !preparationServiceFrame, preparationFailureWitness == nil, !detached,
              preparationWriterPhase != .installing else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireEraseRetirementOperation(self)
        preparationServiceFrame = true
    }

    func endPreparationServiceFrame() { preparationServiceFrame = false }

    /// The first original-owner EX edge is after durable P and before any
    /// pointer, search, or auxiliary mutation. A failed acquisition remains
    /// sticky on this operation; Coordinator retains any acquired owner.
    func retainOriginalEraseExclusionBeforePointerEffects(
        coordinator: StoreSessionCoordinator,
        store: EraseIntentStore,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2
    ) async throws -> StoreTemporalNormalizationExclusionV1 {
        guard let router, preparationServiceFrame,
              preparationCoordinator === coordinator,
              preparationWriterPhase == .absent,
              preparationWriterAllocation == nil,
              preparationTargetSession == nil,
              transferredExclusion == nil,
              !detached, !detaching,
              preparation.matches(intent),
              intent.phase == .emptyGenerationPrepared,
              try store.load() == intent,
              try store.loadPreparation() == preparation else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
        if originalExclusion == nil {
            if !startedExclusionAcquisition {
                startedExclusionAcquisition = true
                originalExclusion = try await coordinator.drainTemporalProducersForNormalization()
            } else {
                originalExclusion = try coordinator.retryTemporalNormalizationExclusion()
            }
        }
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.exclusion.acquired")
#endif
        guard let originalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // The acquired EX is retained before these fallible post-await checks.
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.exclusion.post-router")
#endif
        guard try store.load() == intent,
              try store.loadPreparation() == preparation else {
            throw AppAccessContractFailureV1.staleAttempt
        }
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.exclusion.post-controls")
#endif
        try originalExclusion.revalidate()
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.exclusion.revalidated")
#endif
        return originalExclusion
    }

    /// The same-process retry may borrow only this operation's already held
    /// original exclusion. A started but missing acquisition is terminal; it
    /// cannot fall through to a new EX or a fresh original owner.
    func requireOriginalEraseRecoveryRetainedExclusion(
        coordinator: StoreSessionCoordinator
    ) throws -> StoreTemporalNormalizationExclusionV1? {
#if DEBUG
        guard originalShutdownState == .active else {
            throw AppAccessContractFailureV1.staleAttempt
        }
#endif
        guard let router, !detached, !detaching,
              preparationCoordinator === coordinator,
              transferredExclusion == nil,
              preparationServiceFrame,
              preparationFailureWitness == nil,
              originalWriterTransition.map({ $0.projected }) ?? true else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
        guard startedExclusionAcquisition == (originalExclusion != nil) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let originalExclusion {
            guard originalAuxiliaryRosterAdmission != nil,
                  originalAuxiliaryStore != nil,
                  originalAuxiliaryProjectedIntent?.phase
                    == .emptyGenerationPrepared else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try originalExclusion.revalidate()
        }
        return originalExclusion
    }

    /// Identity-only under an already held Registry G. No nested census or
    /// exclusion revalidation is permitted from this physical FD callback.
    func retainedOriginalEraseRecoveryExclusionIdentity(
        coordinator: StoreSessionCoordinator
    ) -> StoreTemporalNormalizationExclusionV1? {
#if DEBUG
        guard originalShutdownState == .active else { return nil }
#endif
        guard preparationCoordinator === coordinator,
              !detached, !detaching,
              transferredExclusion == nil else { return nil }
        return originalExclusion
    }

    func requireOriginalRecoveryFirstEffectStore(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        expected: EraseIntentV1
    ) throws -> EraseIntentStore {
        guard originalRecoveryPreOpenOwner === owner,
              owner.retainedOriginalExclusion === originalExclusion,
              let store = originalAuxiliaryStore,
              let admission = originalAuxiliaryRosterAdmission,
              originalAuxiliaryProjectedIntent == expected,
              expected.phase == .emptyGenerationPrepared,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              !detached, !detaching else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try admission.receipt.requireBound(store: store,
            operation: self, seal: admission.seal)
        return store
    }

    func requireOriginalRecoveryProjectedAuxiliaryStore(
        coordinator: StoreSessionCoordinator,
        switched: EraseIntentV1
    ) throws -> EraseIntentStore {
        guard let router,
              preparationCoordinator === coordinator,
              originalRecoveryPreOpenOwner == nil,
              let exclusion = originalExclusion,
              transferredExclusion == nil,
              let store = originalAuxiliaryStore,
              let admission = originalAuxiliaryRosterAdmission,
              originalAuxiliaryProjectedIntent == switched,
              switched.phase == .pointerSwitched,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              !detached, !detaching else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
        try exclusion.revalidate()
        try admission.receipt.requireBound(store: store,
            operation: self, seal: admission.seal)
        guard try store.load() == switched else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return store
    }

    /// The AppAccess activation callback reports failure through its pending
    /// state rather than throwing to EraseAllService. Reprove the actual
    /// installed target pair before publishing the R intent phase.
    func requireOriginalEraseTargetInstalledBeforePhaseCAS(
        _ target: StoreGenerationSession
    ) throws {
        guard let coordinator = preparationCoordinator,
              let exclusion = originalExclusion,
              let allocation = preparationWriterAllocation,
              let transition = originalWriterTransition,
              transition.projected,
              transition.targetAllocation === allocation,
              transition.registry === exclusion.registry,
              preparationWriterPhase == .installed,
              originalTargetReaderHandle != nil,
              originalTargetReaderProjection != nil,
              originalTargetReaderProjectedSnapshot != nil,
              !originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              preparationTargetSession === target,
              originalAuxiliaryProjectedIntent?.phase == .pointerSwitched,
              originalAuxiliaryStore != nil,
              originalAuxiliaryRosterAdmission != nil,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              !detached, !detaching else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireRecoveryExecution(coordinator: coordinator)
        try coordinator.requireOriginalEraseTargetInstalledUnderRetainedExclusion(
            allocation, session: target, operation: self,
            exclusion: exclusion)
    }

    /// Called only within the original recovery owner's already-held G.
    /// Its checked Registry observer supplies the exact frozen first cohort;
    /// neither this scope nor the Store opens a second mutation lock.
    func withOriginalRecoveryAuxiliaryPhaseInsideHeldG<T>(
        store: EraseIntentStore,
        expected: EraseIntentV1,
        replacement: EraseIntentV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        permit: OriginalEraseRecoveryFirstEffectPermitV1,
        _ body: () throws -> T
    ) throws -> T {
        try permit.requireHeld()
        guard originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == expected,
              expected.phase == .emptyGenerationPrepared,
              replacement == expected.advancing(to: .pointerSwitched),
              originalRecoveryPreOpenOwner != nil,
              originalExclusion?.registry === registry,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalAuxiliaryPhaseCASInFlight = true
        do {
            let prior = try requireOriginalEraseAuxiliaryPhaseUnderHeldG(
                registry: registry, activity: activity, store: store,
                expected: expected, replacement: replacement)
            try registry.requireOriginalEraseAuxiliaryFirstCensusInsideRecoveryG(
                activity: activity, operation: self, store: store,
                expected: expected, replacement: replacement,
                frozen: prior, permit: permit)
            let result = try body()
            try registry.requireOriginalEraseAuxiliaryFirstCensusInsideRecoveryG(
                activity: activity, operation: self, store: store,
                expected: expected, replacement: replacement,
                frozen: prior, permit: permit)
            originalAuxiliaryPhaseCASInFlight = false
            return result
        } catch {
            originalAuxiliaryPhaseCASUncertain = true
            throw error
        }
    }

    /// A separate P-cut effect, before the retired pointer temp and before
    /// the P→Q CAS. The Registry checks the exact first cohort on both sides;
    /// this operation only vouches for its original Store and retained EX.
    func withOriginalRecoveryRetiredCommitmentInsideHeldG<T>(
        store: EraseIntentStore,
        expected: EraseIntentV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        permit: OriginalEraseRecoveryRetiredCommitmentPermitV1,
        _ body: () throws -> T
    ) throws -> T {
        try permit.requireHeld()
        guard originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == expected,
              expected.schemaVersion == 2,
              expected.phase == .emptyGenerationPrepared,
              originalRecoveryPreOpenOwner != nil,
              originalRetiredCommitmentReceipt == nil,
              !originalRetiredCommitmentInFlight,
              !originalRetiredCommitmentUncertain,
              originalExclusion?.registry === registry,
              let frozen = originalAuxiliaryFirstLeaseCensus else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalRetiredCommitmentInFlight = true
        do {
            try registry.requireOriginalEraseRetiredCommitmentFirstCensusInsideRecoveryG(
                activity: activity, operation: self, store: store,
                expected: expected, frozen: frozen, permit: permit)
            let result = try body()
            try registry.requireOriginalEraseRetiredCommitmentFirstCensusInsideRecoveryG(
                activity: activity, operation: self, store: store,
                expected: expected, frozen: frozen, permit: permit)
            originalRetiredCommitmentInFlight = false
            return result
        } catch {
            originalRetiredCommitmentUncertain = true
            throw error
        }
    }

    /// Identity-only callback from the Registry's held G; no Store read,
    /// nested lock acquisition or new physical observation occurs here.
    func requireOriginalEraseRetiredCommitmentUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore,
        expected: EraseIntentV1
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, !detached, !detaching,
              originalRetiredCommitmentInFlight,
              !originalRetiredCommitmentUncertain,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == expected,
              expected.schemaVersion == 2,
              expected.phase == .emptyGenerationPrepared,
              originalAuxiliaryRosterAdmission != nil,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let first = originalAuxiliaryFirstLeaseCensus,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              let source = preparationSourceWriter,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: source.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        return first
    }

    func retainOriginalRecoveryRetiredCommitment(
        _ receipt: EraseIntentStore.OriginalRecoveryRetiredCommitmentReceiptV1,
        store: EraseIntentStore,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        namespace: OriginalEraseRecoveryNamespaceSnapshotV1,
        replacementBytes: Data
    ) throws {
        guard originalRetiredCommitmentReceipt == nil,
              !originalRetiredCommitmentInFlight,
              !originalRetiredCommitmentUncertain,
              originalAuxiliaryStore === store,
              originalRecoveryPreOpenOwner === owner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try receipt.requireBound(operation: self, owner: owner,
            namespace: namespace, replacementBytes: replacementBytes)
        originalRetiredCommitmentReceipt = receipt
    }

    /// The second, separately minted G scope may publish only the private
    /// stage inode record, after the first P commitment is durable. This
    /// wrapper never accepts an observed same-name stage as operation-owned.
    func withOriginalRecoveryRetiredStageIdentityInsideHeldG<T>(
        store: EraseIntentStore,
        expected: EraseIntentV1,
        commitment: EraseIntentStore.OriginalRecoveryRetiredCommitmentReceiptV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        permit: OriginalEraseRecoveryRetiredStagePermitV1,
        _ body: () throws -> T
    ) throws -> T {
        try permit.requireHeld()
        guard originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == expected,
              expected.schemaVersion == 2,
              expected.phase == .emptyGenerationPrepared,
              originalRecoveryPreOpenOwner != nil,
              originalRetiredCommitmentReceipt === commitment,
              !originalRetiredStageIdentityPublished,
              !originalRetiredStageIdentityInFlight,
              !originalRetiredStageIdentityUncertain,
              originalExclusion?.registry === registry,
              let frozen = originalAuxiliaryFirstLeaseCensus else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalRetiredStageIdentityInFlight = true
        do {
            try registry.requireOriginalEraseRetiredStageFirstCensusInsideRecoveryG(
                activity: activity, operation: self, store: store,
                expected: expected, frozen: frozen, permit: permit)
            let result = try body()
            try registry.requireOriginalEraseRetiredStageFirstCensusInsideRecoveryG(
                activity: activity, operation: self, store: store,
                expected: expected, frozen: frozen, permit: permit)
            originalRetiredStageIdentityInFlight = false
            originalRetiredStageIdentityPublished = true
            return result
        } catch {
            originalRetiredStageIdentityUncertain = true
            throw error
        }
    }

    /// Called only by the Registry under its already-held G; all physical
    /// reproof stays in the Store/Factory effects, outside this callback.
    func requireOriginalEraseRetiredStageUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore,
        expected: EraseIntentV1
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, !detached, !detaching,
              originalRetiredStageIdentityInFlight,
              !originalRetiredStageIdentityUncertain,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == expected,
              expected.schemaVersion == 2,
              expected.phase == .emptyGenerationPrepared,
              originalRetiredCommitmentReceipt != nil,
              originalAuxiliaryRosterAdmission != nil,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let first = originalAuxiliaryFirstLeaseCensus,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              let source = preparationSourceWriter,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: source.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        return first
    }

    /// The original P owner retains both observation owners before their
    /// first descriptor or tree read. This captures data only; publication
    /// and the currently unmintable roster admission remain separate.
    func captureOriginalEraseAuxiliaryFirstObservation(
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator,
        cachesDirectoryURL: URL,
        temporaryDirectoryURL: URL
    ) async throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.aux.capture.enter")
#endif
        guard originalAuxiliaryStore == nil ||
              originalAuxiliaryStore === store else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalAuxiliaryStore = store
        let exclusion = try await retainOriginalEraseExclusionBeforePointerEffects(
            coordinator: coordinator, store: store,
            intent: intent, preparation: preparation)
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.aux.exclusion-returned")
#endif
        guard !originalAuxiliaryFirstCaptureAttempted,
              originalAuxiliaryFirstObserver == nil,
              originalAuxiliaryFirstCaptureOwner == nil,
              originalAuxiliaryFirstSnapshot == nil,
              originalAuxiliaryFirstIntent == nil,
              originalAuxiliaryFirstPreparation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // A fresh original P owner must not incorporate an interrupted older
        // reader publication into its immutable Operations first image. The
        // Registry checks the reserved record/temp names under this retained
        // EX and actual G, using operation-retained checked observation FDs.
        guard let source = preparationSourceWriter,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              source.token == exclusion.retainedWriter,
              originalAuxiliaryRegistryObservationScope == nil,
              !originalAuxiliaryRegistryObservationFailed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let readerProbeActivity = try exclusion
            .requireOriginalEraseAuxiliaryPhaseActivity(
                registry: registry, coordinator: coordinator,
                writer: source.token)
        originalAuxiliaryRegistryObservationScope =
            .preFirstReaderRecordProbe
        do {
            try registry.requireOriginalEraseRetainedReaderRecordAbsent(
                operation: self, activity: readerProbeActivity)
            originalAuxiliaryRegistryObservationScope = nil
        } catch {
            originalAuxiliaryRegistryObservationFailed = true
            originalAuxiliaryRegistryObservationScope = nil
            throw error
        }
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.aux.first-guard-passed")
#endif
        originalAuxiliaryFirstCaptureAttempted = true
        originalAuxiliaryFirstIntent = intent
        originalAuxiliaryFirstPreparation = preparation
        let observer = EraseSchema2ColdAuxiliaryFirstObserverV1()
        originalAuxiliaryFirstObserver = observer
        let owner = try StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1(
            cachesURL: cachesDirectoryURL,
            temporaryURL: temporaryDirectoryURL,
            observer: observer)
        originalAuxiliaryFirstCaptureOwner = owner
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.aux.owner-created")
#endif
        let snapshot = try owner.captureFirst(
            operation: self, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation, store: store)
        originalAuxiliaryFirstSnapshot = snapshot
        originalTargetReaderStartingImage = .originalP(snapshot)
#if DEBUG
        traceOriginalAuxiliaryFixedStageForTesting(
            "original.aux.snapshot-captured")
#endif
        return snapshot
    }

    func requireOriginalEraseAuxiliaryFirstCaptureOwner(
        _ owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore
    ) throws {
        guard let router, !detached, !detaching,
              originalAuxiliaryFirstCaptureAttempted,
              originalAuxiliaryFirstObserver === observer,
              originalAuxiliaryFirstCaptureOwner === owner,
              originalAuxiliaryFirstIntent == intent,
              originalAuxiliaryFirstPreparation == preparation,
              originalAuxiliaryStore === store,
              originalExclusion === exclusion,
              transferredExclusion == nil,
              preparationCoordinator === coordinator,
              preparationServiceFrame,
              preparationWriterPhase == .absent,
              preparationFailureWitness == nil,
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared,
              preparation.matches(intent),
              try store.load() == intent,
              try store.loadPreparation() == preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
        try exclusion.revalidate()
    }

    func captureOriginalEraseAuxiliaryPhysicalRoster(
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws -> EraseSchema2ColdAuxiliaryPhysicalRosterV1 {
        guard !originalAuxiliaryRosterCaptureAttempted,
              originalAuxiliaryRosterCapture == nil,
              originalAuxiliaryFirstPhysicalRoster == nil,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let observer = originalAuxiliaryFirstObserver,
              let snapshot = originalAuxiliaryFirstSnapshot,
              let exclusion = originalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireOriginalEraseAuxiliaryFirstCaptureOwner(
            owner, observer: observer, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation, store: store)
        guard try owner.requireFirst() == snapshot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalAuxiliaryRosterCaptureAttempted = true
        let capture = EraseSchema2OriginalAuxiliaryRosterCaptureV1()
        originalAuxiliaryRosterCapture = capture
        let roster = try owner.captureFirstPhysicalRoster(
            capture: capture, operation: self,
            coordinator: coordinator, exclusion: exclusion,
            intent: intent, preparation: preparation, store: store)
        originalAuxiliaryFirstPhysicalRoster = roster
        return roster
    }

    func requireOriginalEraseAuxiliaryRosterCapture(
        _ capture: EraseSchema2OriginalAuxiliaryRosterCaptureV1,
        owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        snapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore
    ) throws {
        guard originalAuxiliaryRosterCaptureAttempted,
              originalAuxiliaryRosterCapture === capture,
              originalAuxiliaryFirstPhysicalRoster == nil,
              originalAuxiliaryFirstSnapshot == snapshot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireOriginalEraseAuxiliaryFirstCaptureOwner(
            owner, observer: observer, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation, store: store)
    }

    /// The Store's in-flight pre-rename and post-finish witness cannot load
    /// through its own busy file owner. This proves the same original EX,
    /// operation and retained first parent identities without Store recursion.
    func requireOriginalAuxiliaryRosterPhysicalReproof(
        capture: EraseSchema2OriginalAuxiliaryRosterCaptureV1,
        owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        snapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2
    ) throws {
        guard let router, !detached, !detaching,
              originalAuxiliaryRosterCaptureAttempted,
              originalAuxiliaryRosterCapture === capture,
              originalAuxiliaryFirstCaptureOwner === owner,
              originalAuxiliaryFirstObserver === observer,
              originalAuxiliaryFirstSnapshot == snapshot,
              originalAuxiliaryFirstIntent == intent,
              originalAuxiliaryFirstPreparation == preparation,
              originalAuxiliaryStore != nil,
              originalExclusion === exclusion,
              preparationCoordinator === coordinator,
              preparationServiceFrame,
              preparationWriterPhase == .absent,
              preparationFailureWitness == nil,
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared,
              preparation.matches(intent) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
        try exclusion.revalidate()
        guard try owner.requireFirst() == snapshot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainOriginalAuxiliaryRosterPublicationSeal(
        _ seal: EraseSchema2OriginalAuxiliaryRosterPublicationSealV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard !originalAuxiliaryRosterSealAttempted,
              originalAuxiliaryRosterSeal == nil,
              let capture = originalAuxiliaryRosterCapture,
              let observer = originalAuxiliaryFirstObserver,
              let snapshot = originalAuxiliaryFirstSnapshot,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let exclusion = originalExclusion,
              let first = originalAuxiliaryFirstPhysicalRoster else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalAuxiliaryRosterSealAttempted = true
        originalAuxiliaryRosterSeal = seal
        try requireOriginalAuxiliaryRosterPhysicalReproof(
            capture: capture, owner: owner, observer: observer,
            snapshot: snapshot, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation)
        try seal.requireBound(capture: capture, observer: observer,
            snapshot: snapshot, owner: owner, operation: self,
            coordinator: coordinator, exclusion: exclusion,
            intent: intent, preparation: preparation, store: store)
        guard seal.canonicalBytes == first.canonicalBytes,
              seal.canonicalSHA256 == first.canonicalSHA256,
              try store.load() == intent,
              try store.loadPreparation() == preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func sealOriginalEraseAuxiliaryPhysicalRoster(
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws -> EraseSchema2OriginalAuxiliaryRosterPublicationSealV1 {
        guard !originalAuxiliaryRosterSealAttempted,
              originalAuxiliaryRosterSeal == nil,
              let capture = originalAuxiliaryRosterCapture,
              let observer = originalAuxiliaryFirstObserver,
              let snapshot = originalAuxiliaryFirstSnapshot,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let exclusion = originalExclusion,
              let first = originalAuxiliaryFirstPhysicalRoster else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let current = try owner.requireSameFirstPhysicalRoster(
            capture: capture, operation: self,
            coordinator: coordinator, exclusion: exclusion,
            intent: intent, preparation: preparation)
        guard current.canonicalSHA256 == first.canonicalSHA256,
              current.canonicalBytes == first.canonicalBytes else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let seal = try capture.sealOriginal(intent: intent,
            preparation: preparation, observer: observer,
            snapshot: snapshot, owner: owner, operation: self,
            coordinator: coordinator, exclusion: exclusion,
            store: store)
        try retainOriginalAuxiliaryRosterPublicationSeal(
            seal, intent: intent, preparation: preparation,
            store: store, coordinator: coordinator)
        return seal
    }

    /// This under-effect callback has no Store load: Store is holding its own
    /// publication latch. The one retained original seal remains bound to
    /// the complete first physical trees right before rename and after fsync.
    func requireOriginalAuxiliaryRosterSourceFactsBeforeRename(
        seal: EraseSchema2OriginalAuxiliaryRosterPublicationSealV1,
        store: EraseIntentStore
    ) throws {
        guard originalAuxiliaryRosterSealAttempted,
              originalAuxiliaryRosterSeal === seal,
              originalAuxiliaryStore === store,
              let intent = originalAuxiliaryFirstIntent,
              let preparation = originalAuxiliaryFirstPreparation,
              let coordinator = preparationCoordinator,
              let capture = originalAuxiliaryRosterCapture,
              let observer = originalAuxiliaryFirstObserver,
              let snapshot = originalAuxiliaryFirstSnapshot,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let exclusion = originalExclusion,
              let first = originalAuxiliaryFirstPhysicalRoster else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireOriginalAuxiliaryRosterPhysicalReproof(
            capture: capture, owner: owner, observer: observer,
            snapshot: snapshot, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation)
        try seal.requireBound(capture: capture, observer: observer,
            snapshot: snapshot, owner: owner, operation: self,
            coordinator: coordinator, exclusion: exclusion,
            intent: intent, preparation: preparation, store: store)
        let current = try owner.requireSameFirstPhysicalRoster(
            capture: capture, operation: self,
            coordinator: coordinator, exclusion: exclusion,
            intent: intent, preparation: preparation)
        guard current.canonicalSHA256 == first.canonicalSHA256,
              current.canonicalBytes == first.canonicalBytes,
              seal.canonicalSHA256 == first.canonicalSHA256,
              seal.canonicalBytes == first.canonicalBytes else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// The admission is one-way and is minted only from this Store's checked
    /// O_EXCL/rename/fsync/readback receipt and the immutable first full
    /// auxiliary image. The record itself grants no deletion authority.
    func bindOriginalEraseAuxiliaryRosterPublication(
        seal: EraseSchema2OriginalAuxiliaryRosterPublicationSealV1,
        receipt: EraseIntentStore.OriginalAuxiliaryRosterPublicationReceiptV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws -> EraseOriginalAuxiliaryRosterPublicationAdmissionV1 {
        guard originalAuxiliaryRosterAdmission == nil,
              originalAuxiliaryRosterSeal === seal,
              originalAuxiliaryFirstIntent == intent,
              originalAuxiliaryFirstPreparation == preparation,
              originalAuxiliaryStore === store,
              preparationCoordinator === coordinator,
              receipt.canonicalBytes == seal.canonicalBytes,
              receipt.recordFact.mode & S_IFMT == S_IFREG,
              receipt.recordFact.links == 1 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try receipt.requireBound(store: store,
            operation: self, seal: seal)
        try requireOriginalAuxiliaryRosterSourceFactsBeforeRename(
            seal: seal, store: store)
        guard let exclusion = originalExclusion,
              let source = preparationSourceWriter,
              preparationRegistry === exclusion.registry,
              preparationWriterPhase == .absent,
              originalAuxiliaryFirstLeaseCensus == nil,
              originalAuxiliaryRegistryObservationScope == nil,
              !originalAuxiliaryRegistryObservationFailed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: exclusion.registry, coordinator: coordinator,
            writer: source.token)
        originalAuxiliaryRegistryObservationScope = .firstRosterCensus
        do {
            let firstLeases = try exclusion.registry
                .observeOriginalEraseAuxiliaryRegistryChecked(
                    activity: activity, operation: self)
            try inventory.requirePreparationCensus(firstLeases,
                registry: exclusion.registry, sourceWriter: source,
                writer: nil)
            guard firstLeases.filter({ $0.role == .writer }) == [source.token],
                  Set(firstLeases.map(\.leaseID)).count == firstLeases.count else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let admission = EraseOriginalAuxiliaryRosterPublicationAdmissionV1(
                seal: seal, receipt: receipt)
            originalAuxiliaryFirstLeaseCensus = firstLeases
            originalAuxiliaryRosterAdmission = admission
            originalAuxiliaryProjectedIntent = intent
            originalAuxiliaryRegistryObservationScope = nil
            return admission
        } catch {
            originalAuxiliaryRegistryObservationFailed = true
            originalAuxiliaryRegistryObservationScope = nil
            throw error
        }
    }

    /// Original P keeps the old Coordinator and its EX-bound writer. Reprove
    /// the published first auxiliary image and read the ledger through that
    /// exact retained context; a fresh current-reader allocation would try
    /// to acquire an ordinary temporal activity inside the held exclusion.
    func requireOriginalEraseRetainedSourceLedgerBeforePointer(
        intent: EraseIntentV1,
        store: EraseIntentStore,
        factory: StoreGenerationFactory,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard let router, !detached, !detaching,
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared,
              originalAuxiliaryFirstIntent == intent,
              originalAuxiliaryProjectedIntent == intent,
              let preparation = originalAuxiliaryFirstPreparation,
              preparation.matches(intent),
              let admission = originalAuxiliaryRosterAdmission,
              let seal = originalAuxiliaryRosterSeal,
              admission.seal === seal,
              originalAuxiliaryStore === store,
              let coordinator = preparationCoordinator,
              let exclusion = originalExclusion,
              preparationRegistry === exclusion.registry,
              let source = preparationSourceWriter,
              source.token == exclusion.retainedWriter,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              try factory.makeGenerationLeaseRegistry() === exclusion.registry,
              authority.matchesMutationRegistryForOriginalErase(
                exclusion.registry) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try admission.receipt.requireBound(store: store,
            operation: self, seal: seal)
        try store.requireOriginalEraseAuxiliaryPublishedRoster(
            admission.receipt)
        guard try store.load() == intent,
              try store.loadPreparation() == preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireOriginalAuxiliaryRosterSourceFactsBeforeRename(
            seal: seal, store: store)
        try factory.requireOriginalEraseRetainedSourceLedger(
            intent: intent, coordinator: coordinator, authority: authority)
    }

    /// The two original P pointer controls each have a separate one-way
    /// effect boundary. An error after beginning either effect leaves this
    /// operation uncertain; a later cold owner must classify the durable cut.
    func beginOriginalEraseRetainedPointerEffect(
        _ stage: OriginalEraseRetainedPointerStageV1,
        intent: EraseIntentV1,
        store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1
    ) throws -> GenerationTemporalActivityHandleV1 {
        guard let router, !detached, !detaching,
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared,
              originalAuxiliaryProjectedIntent == intent,
              originalAuxiliaryStore === store,
              let admission = originalAuxiliaryRosterAdmission,
              let preparation = originalAuxiliaryFirstPreparation,
              preparation.matches(intent),
              let coordinator = preparationCoordinator,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let source = preparationSourceWriter,
              source.token == exclusion.retainedWriter,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              originalPointerMutationInFlight == nil,
              !originalPointerMutationUncertain,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        switch stage {
        case .current:
            guard !originalPointerPublished,
                  !originalRetiredPublished,
                  originalCurrentPointerReceipt == nil,
                  originalRetiredPointerReceipt == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        case .retired:
            guard originalPointerPublished,
                  !originalRetiredPublished,
                  originalCurrentPointerReceipt != nil,
                  originalRetiredPointerReceipt == nil,
                  originalPointerAuthority != nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        try router.requireEraseRetirementOperation(self)
        try admission.receipt.requireBound(store: store,
            operation: self, seal: admission.seal)
        try store.requireOriginalEraseAuxiliaryPublishedRoster(
            admission.receipt)
        guard try store.load() == intent,
              try store.loadPreparation() == preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: source.token)
        originalPointerMutationInFlight = stage
        return activity
    }

    /// Called only inside the already held G. The Registry performs checked
    /// complete-census reads before and after the actual pointer effect.
    func requireOriginalEraseRetainedPointerUnderHeldG(
        stage: OriginalEraseRetainedPointerStageV1,
        intent: EraseIntentV1,
        store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, !detached, !detaching,
              originalPointerMutationInFlight == stage,
              !originalPointerMutationUncertain,
              originalAuxiliaryProjectedIntent == intent,
              originalAuxiliaryStore === store,
              originalAuxiliaryRosterAdmission != nil,
              let first = originalAuxiliaryFirstLeaseCensus,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let source = preparationSourceWriter,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: source.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        return first
    }

    func requireOriginalEraseCurrentPointerReceipt(
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreRestoreGenerationAuthority.OriginalErasePointerReceiptV1 {
        guard let receipt = originalCurrentPointerReceipt,
              let retained = originalPointerAuthority,
              retained === authority,
              originalPointerPublished,
              !originalPointerMutationUncertain else {
            #if DEBUG
            print("ORIGINAL_POINTER_RETIRED_ROUTE_V1 stage=current-receipt-guard")
            #endif
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try receipt.requireBound(authority: authority,
            operation: self, stage: .current, predecessor: nil)
        return receipt
    }

    func observedOriginalEraseCurrentIDIfPublished(
        authority: StoreRestoreGenerationAuthority
    ) throws -> UUID? {
        guard originalCurrentPointerReceipt != nil else { return nil }
        return try requireOriginalEraseCurrentPointerReceipt(
            authority: authority).currentGenerationID()
    }

    func observedOriginalEraseRetiredIDsIfPublished(
        authority: StoreRestoreGenerationAuthority
    ) throws -> [UUID]? {
        guard originalCurrentPointerReceipt != nil else {
            #if DEBUG
            print("ORIGINAL_POINTER_RETIRED_ROUTE_V1 stage=no-current-receipt")
            #endif
            return nil
        }
        if originalRetiredPointerReceipt != nil {
            return try requireOriginalEraseRetiredPointerReceipt(
                authority: authority).retiredGenerationIDs()
        }
        return try requireOriginalEraseCurrentPointerReceipt(
            authority: authority).retiredGenerationIDs()
    }

    func finishOriginalEraseRetainedPointerEffect(
        _ stage: OriginalEraseRetainedPointerStageV1,
        receipt: StoreRestoreGenerationAuthority.OriginalErasePointerReceiptV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard originalPointerMutationInFlight == stage,
              !originalPointerMutationUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let predecessor: StoreRestoreGenerationAuthority
            .OriginalErasePointerReceiptV1?
        switch stage {
        case .current:
            guard originalCurrentPointerReceipt == nil,
                  originalRetiredPointerReceipt == nil,
                  originalPointerAuthority == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            predecessor = nil
        case .retired:
            guard let current = originalCurrentPointerReceipt,
                  originalRetiredPointerReceipt == nil,
                  originalPointerAuthority === authority else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            predecessor = current
        }
        try receipt.requireBound(authority: authority, operation: self,
            stage: stage, predecessor: predecessor)
        switch stage {
        case .current:
            originalPointerAuthority = authority
            originalCurrentPointerReceipt = receipt
            originalPointerPublished = true
        case .retired:
            originalRetiredPointerReceipt = receipt
            originalRetiredPublished = true
        }
        originalPointerMutationInFlight = nil
    }

    /// The original P writer receipt retains its exact issuing authority.
    /// A later recovery-only read authority must never impersonate that
    /// issuer; Service separately reobserves its current/retired bytes.
    func requireOriginalEraseRetiredPointerReceiptFromIssuer()
        throws -> StoreRestoreGenerationAuthority.OriginalErasePointerReceiptV1 {
        guard let authority = originalPointerAuthority else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try requireOriginalEraseRetiredPointerReceipt(
            authority: authority)
    }

    func requireOriginalEraseRetiredPointerReceipt(
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreRestoreGenerationAuthority.OriginalErasePointerReceiptV1 {
        guard originalPointerAuthority === authority,
              let current = originalCurrentPointerReceipt,
              let retired = originalRetiredPointerReceipt,
              originalPointerPublished, originalRetiredPublished,
              originalPointerMutationInFlight == nil,
              !originalPointerMutationUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try retired.requireBound(authority: authority, operation: self,
            stage: .retired, predecessor: current)
        return retired
    }

    func failOriginalEraseRetainedPointerEffect() {
        originalPointerMutationUncertain = true
    }

    /// Factory retains this exact allocation on the original operation before
    /// the reader's random token, durable record or Registry replacement.
    func retainOriginalEraseTargetReaderAllocation(
        _ allocation: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1,
        epoch: GenerationEpochV1,
        factory: StoreGenerationFactory,
        authority: StoreRestoreGenerationAuthority,
        expectedPointerData: Data
    ) throws -> GenerationTemporalActivityHandleV1 {
        guard let router, !detached, !detaching,
              originalTargetReaderAllocation == nil,
              originalTargetReaderHandle == nil,
              !originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              originalPointerPublished, originalRetiredPublished,
              originalPointerMutationInFlight == nil,
              !originalPointerMutationUncertain,
              let intent = originalAuxiliaryProjectedIntent,
              intent.schemaVersion == 2,
              intent.phase == .pointerSwitched,
              let target = intent.targetPointer,
              epoch.generationID == target.generationID,
              epoch.generationManifestSHA256
                == target.generationManifestSHA256,
              originalAuxiliaryRosterAdmission != nil,
              let store = originalAuxiliaryStore,
              let coordinator = preparationCoordinator,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let source = preparationSourceWriter,
              source.token == exclusion.retainedWriter,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              allocation.matches(registry: registry),
              authority.matchesMutationRegistryForOriginalErase(registry),
              try factory.makeGenerationLeaseRegistry() === registry,
              try store.load() == intent,
              let preparation = try store.loadPreparation(),
              preparation.matches(intent) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: source.token)
        // Bind the checked pointer-writer receipt to its original
        // authority. The recovery authority is a distinct reader of the
        // same Registry and must independently verify current bytes.
        guard let pointerAuthority = originalPointerAuthority,
              pointerAuthority.matchesMutationRegistryForOriginalErase(registry)
        else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireOriginalEraseRetiredPointerReceipt(
            authority: pointerAuthority)
        try factory.requireOriginalEraseCurrentPointerBytes(
            expectedPointerData, identity: target, authority: authority)
        originalTargetReaderAllocation = allocation
        originalTargetReaderInFlight = true
        originalTargetReaderFactory = factory
        originalTargetReaderAuthority = authority
        originalTargetReaderExpectedPointerData = expectedPointerData
        return activity
    }

    /// Pure G-held proof. Registry independently checks the complete prior
    /// array and then exactly prior plus this allocation's one target reader.
    func requireOriginalEraseTargetReaderAdmissionUnderHeldG(
        allocation: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        expectedPointerData: Data
    ) throws -> (intent: EraseIntentV1,
                 priorTokens: [GenerationLeaseTokenV1]) {
        guard let router, !detached, !detaching,
              originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              originalTargetReaderAllocation === allocation,
              originalTargetReaderExpectedPointerData
                == expectedPointerData,
              allocation.matches(registry: registry),
              originalPointerPublished, originalRetiredPublished,
              let intent = originalAuxiliaryProjectedIntent,
              intent.phase == .pointerSwitched,
              let target = intent.targetPointer,
              let factory = originalTargetReaderFactory,
              let authority = originalTargetReaderAuthority,
              let first = originalAuxiliaryFirstLeaseCensus,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let source = preparationSourceWriter,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: source.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        // Bind the checked pointer-writer receipt to its original
        // authority. The recovery authority is a distinct reader of the
        // same Registry and must independently verify current bytes.
        guard let pointerAuthority = originalPointerAuthority,
              pointerAuthority.matchesMutationRegistryForOriginalErase(registry)
        else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireOriginalEraseRetiredPointerReceipt(
            authority: pointerAuthority)
        try factory.requireOriginalEraseCurrentPointerBytes(
            expectedPointerData, identity: target, authority: authority)
        return (intent, first)
    }

    /// Identity-only owner proof under the Registry's already held G.
    func requireOriginalEraseTargetReaderStartingProjectionOwner(
        _ sealed: OriginalRecoveryPostPointerAuxiliaryProjectionV1,
        recoveryOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        allocation: GenerationLeaseAllocationAttemptV1,
        owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1
    ) throws {
        guard let router, !detached, !detaching,
              originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              originalTargetReaderAllocation === allocation,
              originalTargetReaderHandle == nil,
              originalTargetReaderProjection == nil,
              let startingImage = originalTargetReaderStartingImage,
              case .retainedRecovery(let issued, let issuedOwner) = startingImage,
              issued === sealed, issuedOwner === recoveryOwner,
              originalRecoveryAuxiliaryFirstMatchesOriginalP,
              originalRecoveryPostPointerAuxiliaryProjection === sealed,
              originalRecoveryPostPointerOwner === recoveryOwner,
              originalRecoveryPreOpenOwner == nil,
              originalAuxiliaryFirstCaptureOwner === owner,
              preparationCoordinator === coordinator,
              originalExclusion === exclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              allocation.matches(registry: registry),
              originalAuxiliaryProjectedIntent?.phase == .pointerSwitched,
              let source = preparationSourceWriter,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: source.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
    }

    /// This normal issuer is the same original P capture owner, not a
    /// recovery owner. Reprove its original Store/roster and actual pointer
    /// publication under the Registry's held G on both sides of the scan.
    func requireOriginalEraseTargetReaderNormalStartingOwner(
        originalP: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        allocation: GenerationLeaseAllocationAttemptV1,
        owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1
    ) throws {
        guard let startingImage = originalTargetReaderStartingImage,
              case .originalP(let issued) = startingImage,
              issued == originalP,
              originalAuxiliaryFirstSnapshot == originalP,
              originalAuxiliaryFirstCaptureAttempted,
              originalAuxiliaryFirstCaptureOwner === owner,
              originalAuxiliaryFirstObserver === observer,
              let firstIntent = originalAuxiliaryFirstIntent,
              firstIntent.schemaVersion == 2,
              firstIntent.phase == .emptyGenerationPrepared,
              let preparation = originalAuxiliaryFirstPreparation,
              preparation.matches(firstIntent),
              let intent = originalAuxiliaryProjectedIntent,
              intent == firstIntent.advancing(to: .pointerSwitched),
              let store = originalAuxiliaryStore,
              let admission = originalAuxiliaryRosterAdmission,
              admission.seal === originalAuxiliaryRosterSeal,
              originalAuxiliaryFirstPhysicalRoster != nil,
              preparationCoordinator === coordinator,
              preparationServiceFrame,
              preparationFailureWitness == nil,
              originalExclusion === exclusion,
              transferredExclusion == nil,
              originalRecoveryObservation == nil,
              originalRecoveryPreOpenOwner == nil,
              originalRecoveryAuxiliaryContinuity == nil,
              !originalRecoveryAuxiliaryFirstMatchesOriginalP,
              originalRecoveryPostPointerAuxiliaryProjection == nil,
              originalRecoveryPostPointerOwner == nil,
              originalTargetReaderHandle == nil,
              originalTargetReaderProjection == nil,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              let pointerData = originalTargetReaderExpectedPointerData else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let checked = try requireOriginalEraseTargetReaderAdmissionUnderHeldG(
            allocation: allocation, registry: registry, activity: activity,
            expectedPointerData: pointerData)
        guard checked.intent == intent else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try admission.receipt.requireBound(store: store,
            operation: self, seal: admission.seal)
        try store.requireOriginalEraseAuxiliaryPublishedRoster(admission.receipt)
        guard try store.load() == intent,
              try store.loadPreparation() == preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// The Registry has twice observed the physical tree while holding its
    /// actual G and before the first reader-record O_EXCL. Normal original P
    /// uses its immutable unchanged image; retained recovery uses its checked
    /// P-to-Scratch projection. Neither can adopt a current Q survivor.
    func requireOriginalEraseTargetReaderFirstOperationsUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        operationsFact: String,
        operationsDigest: String,
        leaseRootFact: String,
        leaseDigest: String
    ) throws {
        guard let router, !detached, !detaching,
              originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              originalTargetReaderHandle == nil,
              originalTargetReaderProjection == nil,
              originalAuxiliaryRosterAdmission != nil,
              let snapshot = originalAuxiliaryFirstSnapshot,
              let startingImage = originalTargetReaderStartingImage,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let allocation = originalTargetReaderAllocation,
              let coordinator = preparationCoordinator,
              originalAuxiliaryProjectedIntent?.phase == .pointerSwitched,
              originalPointerPublished, originalRetiredPublished,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let source = preparationSourceWriter,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: source.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        let starting: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
        switch startingImage {
        case .originalP(let issued):
            guard issued == snapshot else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            starting = try owner.requireOriginalReaderStartingUnchanged(
                originalP: issued, allocation: allocation,
                registry: registry, activity: activity,
                operation: self, coordinator: coordinator,
                exclusion: exclusion)
        case .retainedRecovery(let sealed, let recoveryOwner):
            guard originalRecoveryAuxiliaryFirstMatchesOriginalP,
                  originalRecoveryPostPointerAuxiliaryProjection === sealed,
                  originalRecoveryPostPointerOwner === recoveryOwner else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            starting = try owner.requireOriginalReaderStartingProjected(
                sealed, recoveryOwner: recoveryOwner, originalP: snapshot,
                allocation: allocation, registry: registry, activity: activity,
                operation: self, coordinator: coordinator,
                exclusion: exclusion)
        }
        guard starting.operations == .present(
                rootFact: operationsFact, digest: operationsDigest),
              starting.operationsChildren["generation-leases"]
                == .directory(rootFact: leaseRootFact,
                    digest: leaseDigest) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainOriginalEraseTargetReaderHandle(
        _ handle: GenerationLeaseHandleV1,
        allocation: GenerationLeaseAllocationAttemptV1
    ) throws {
        #if DEBUG
        FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=router.handle-enter\n".utf8))
        #endif
        guard originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              originalTargetReaderAllocation === allocation,
              allocation.allocatedHandle === handle,
              allocation.originalEraseRetainedPublishedToken
                == handle.token,
              originalTargetReaderHandle == nil,
              originalTargetReaderProjection == nil,
              originalTargetReaderProjectedSnapshot == nil,
              let projection = allocation
                .originalEraseRetainedPublicationProjection,
              let exclusion = originalExclusion,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let coordinator = preparationCoordinator else {
            originalTargetReaderUncertain = true
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        #if DEBUG
        FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=router.handle-guard-complete\n".utf8))
        #endif
        do {
            try projection.requireBound(registry: exclusion.registry,
                operation: self, allocation: allocation, handle: handle)
            originalTargetReaderHandle = handle
            originalTargetReaderProjection = projection
            #if DEBUG
            FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=router.projection-enter\n".utf8))
            #endif
            let projected = try owner.requireOriginalReaderProjected(
                projection, allocation: allocation, handle: handle,
                operation: self, coordinator: coordinator,
                exclusion: exclusion)
            #if DEBUG
            FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=router.projection-complete\n".utf8))
            #endif
            originalTargetReaderProjectedSnapshot = projected
            originalTargetReaderInFlight = false
        } catch {
            #if DEBUG
            FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=router.projection-failed\n".utf8))
            #endif
            originalTargetReaderUncertain = true
            throw error
        }
    }

    /// The held parent observer can borrow only this operation's checked
    /// private reader receipt; it cannot rebaseline any postpublication
    /// Operations survivor or grant later deletion authority.
    func requireOriginalEraseTargetReaderProjectionOwner(
        _ projection: OriginalEraseRetainedTargetReaderProjectionV1,
        allocation: GenerationLeaseAllocationAttemptV1,
        handle: GenerationLeaseHandleV1,
        owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard let router, !detached, !detaching,
              originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              originalTargetReaderAllocation === allocation,
              originalTargetReaderHandle === handle,
              originalTargetReaderProjection === projection,
              originalTargetReaderProjectedSnapshot == nil,
              originalAuxiliaryFirstCaptureOwner === owner,
              preparationCoordinator === coordinator,
              originalExclusion === exclusion,
              preparationRegistry === exclusion.registry,
              originalAuxiliaryRosterAdmission != nil,
              originalAuxiliaryFirstPhysicalRoster != nil,
              originalPointerPublished, originalRetiredPublished,
              originalAuxiliaryProjectedIntent?.phase == .pointerSwitched,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              projection.checkedSettled else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try projection.requireBound(registry: exclusion.registry,
            operation: self, allocation: allocation, handle: handle)
    }

    func failOriginalEraseTargetReader() {
        originalTargetReaderUncertain = true
    }

    /// Data-only admission for the same Store's checked P→Q or Q→R intent
    /// CAS. It never constructs a fresh auxiliary roster from survivors.
    func requireOriginalEraseAuxiliaryPhaseOwner(
        store: EraseIntentStore,
        expected: EraseIntentV1,
        replacement: EraseIntentV1
    ) throws {
        guard let admission = originalAuxiliaryRosterAdmission,
              admission.seal === originalAuxiliaryRosterSeal,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == expected,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              replacement == expected.advancing(to:
                expected.phase == .emptyGenerationPrepared
                    ? .pointerSwitched : .sessionActivated),
              expected.phase == .emptyGenerationPrepared
                || expected.phase == .pointerSwitched,
              let exclusion = originalExclusion,
              transferredExclusion == nil,
              preparationCoordinator != nil,
              let router,
              !detached else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try exclusion.revalidate()
        try admission.receipt.requireBound(store: store,
            operation: self, seal: admission.seal)
        if expected.phase == .emptyGenerationPrepared {
            guard let authority = originalPointerAuthority else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            _ = try requireOriginalEraseRetiredPointerReceipt(
                authority: authority)
        }
    }

    /// Called synchronously after Store's full preflight and before Store
    /// changes its phase-in-flight latch. A second full owner check is safe
    /// here; it must not run after that latch because receipt.requireBound
    /// intentionally refuses every ordinary in-flight roster reproof.
    func admitOriginalEraseAuxiliaryPhaseCAS(
        store: EraseIntentStore,
        expected: EraseIntentV1,
        replacement: EraseIntentV1
    ) throws -> OriginalEraseAuxiliaryPhaseCASAdmissionV1 {
        try requireOriginalEraseAuxiliaryPhaseOwner(
            store: store, expected: expected, replacement: replacement)
        guard let receipt = originalAuxiliaryRosterAdmission?.receipt else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return OriginalEraseAuxiliaryPhaseCASAdmissionV1(
            operation: self, store: store, receipt: receipt,
            expected: expected, replacement: replacement)
    }

    /// Brackets the Store's canonical CAS with the *same* retained EX and
    /// Registry G. Failure is terminal for this operation; a fresh operation
    /// must classify its durable cut instead of retrying through this owner.
    func withOriginalEraseAuxiliaryPhaseCAS(
        admission: OriginalEraseAuxiliaryPhaseCASAdmissionV1,
        store: EraseIntentStore,
        expected: EraseIntentV1,
        replacement: EraseIntentV1,
        _ body: () throws -> Void
    ) throws {
        guard let exclusion = originalExclusion,
              let coordinator = preparationCoordinator,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              originalAuxiliaryRosterAdmission?.receipt ===
                admission.receipt,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == expected,
              let writer = expected.phase == .emptyGenerationPrepared
                ? preparationSourceWriter : preparationWriterAllocation?.allocatedHandle,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try admission.begin(operation: self, store: store,
            expected: expected, replacement: replacement)
        try store.requireOriginalEraseAuxiliaryPhaseInFlight(
            receipt: admission.receipt, operation: self,
            expected: expected, replacement: replacement)
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: writer.token)
        originalAuxiliaryPhaseCASInFlight = true
        do {
            try registry.withOriginalEraseAuxiliaryIntentCASUnderRetainedExclusion(
                activity: activity, operation: self, store: store,
                expectedIntent: expected, replacement: replacement, body)
            originalAuxiliaryPhaseCASInFlight = false
        } catch {
            originalAuxiliaryPhaseCASUncertain = true
            throw error
        }
    }

    /// Registry calls this with G already held. No Registry observation,
    /// exclusion revalidation, Store read, or new descriptor is permitted.
    func requireOriginalEraseAuxiliaryPhaseUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore,
        expected: EraseIntentV1,
        replacement: EraseIntentV1
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, !detached, !detaching,
              originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == expected,
              replacement == expected.advancing(to:
                expected.phase == .emptyGenerationPrepared
                    ? .pointerSwitched : .sessionActivated),
              originalAuxiliaryRosterAdmission != nil,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let first = originalAuxiliaryFirstLeaseCensus else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        if expected.phase == .emptyGenerationPrepared {
            guard preparationWriterPhase == .absent,
                  originalWriterTransition == nil,
                  let source = preparationSourceWriter,
                  exclusion.matchesOriginalEraseAuxiliaryPhase(
                    registry: registry, activity: activity,
                    writer: source.token) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return first
        }
        guard expected.phase == .pointerSwitched,
              preparationWriterPhase == .installed,
              let transition = originalWriterTransition,
              transition.projected,
              transition.prior == (try originalAuxiliaryFirstPlusReaderTokens()),
              let target = transition.targetAllocation.allocatedHandle,
              transition.targetAllocation.preparationPublishedToken == target.token,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: target.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return (transition.prior.filter {
            $0.leaseID != transition.oldWriter.token.leaseID
        } + [target.token]).sorted {
            $0.leaseID.uuidString.lowercased()
                < $1.leaseID.uuidString.lowercased()
        }
    }

    /// A distinct read-only Q scope after the pre-open owner has released.
    /// It retains the original EX, Registry, activity, Store and first token
    /// cohort; it cannot authorize target-writer publication or a phase CAS.
    func withOriginalRecoveryPostPointerAuxiliaryRead<Value>(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore,
        intent: EraseIntentV1,
        coordinator: StoreSessionCoordinator,
        _ body: () throws -> Value
    ) throws -> Value {
        guard let router, !detached, !detaching,
              preparationCoordinator === coordinator,
              originalRecoveryPreOpenOwner == nil,
              originalRecoveryAuxiliaryContinuity == nil,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == intent,
              intent.phase == .pointerSwitched,
              originalAuxiliaryRosterAdmission != nil,
              originalAuxiliaryFirstLeaseCensus != nil,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              originalTargetReaderHandle == nil,
              !originalAuxiliaryPhaseCASInFlight,
              !originalAuxiliaryPhaseCASUncertain,
              !originalPostPointerReproofInFlight,
              !originalPostPointerReproofUncertain,
              originalAuxiliaryRegistryObservationScope == nil,
              !originalAuxiliaryRegistryObservationFailed,
              let source = preparationSourceWriter,
              source.token == exclusion.retainedWriter else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
        let checkedActivity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: source.token)
        guard checkedActivity === activity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalPostPointerReproofInFlight = true
        originalAuxiliaryRegistryObservationScope = .postPointerReproof
        do {
            let value = try registry.withOriginalRecoveryPostPointerReadUnderRetainedExclusion(
                activity: activity, operation: self, store: store,
                intent: intent, body)
            originalAuxiliaryRegistryObservationScope = nil
            originalPostPointerReproofInFlight = false
            return value
        } catch {
            originalAuxiliaryRegistryObservationScope = nil
            originalPostPointerReproofInFlight = false
            originalPostPointerReproofUncertain = true
            originalAuxiliaryRegistryObservationFailed = true
            throw error
        }
    }

    /// Identity-only under G. The Registry's checked reader, not this
    /// method, observes the complete physical token cohort.
    func requireOriginalRecoveryPostPointerReproofUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore,
        intent: EraseIntentV1
    ) throws -> [GenerationLeaseTokenV1] {
        guard !detached, !detaching,
              originalPostPointerReproofInFlight,
              !originalPostPointerReproofUncertain,
              originalAuxiliaryRegistryObservationScope == .postPointerReproof,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent == intent,
              intent.phase == .pointerSwitched,
              originalRecoveryPreOpenOwner == nil,
              preparationWriterPhase == .absent,
              originalWriterTransition == nil,
              originalTargetReaderHandle == nil,
              let exclusion = originalExclusion,
              let source = preparationSourceWriter,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: source.token),
              let first = originalAuxiliaryFirstLeaseCensus else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return first
    }

    /// Registry retains each transient registry-leaf FD here before open.
    /// A failed close leaves the attempt in this operation and withholds the
    /// next observation or phase effect; numeric descriptors are never
    /// retried by another owner.
    func retainOriginalEraseAuxiliaryRegistryObservation(
        attempt: EraseSchema2ColdRegistryObservationAttemptV1,
        registry: GenerationLeaseRegistryV1
    ) throws {
        originalAuxiliaryRegistryObservations.removeAll { $0.isCheckedClosed }
        let preFirstReaderRecordProbe =
            originalAuxiliaryRegistryObservationScope
                == .preFirstReaderRecordProbe
            && !originalAuxiliaryFirstCaptureAttempted
            && originalAuxiliaryFirstObserver == nil
            && originalAuxiliaryFirstCaptureOwner == nil
            && originalAuxiliaryRosterAdmission == nil
            && originalAuxiliaryFirstLeaseCensus == nil
            && preparationWriterPhase == .absent
            && preparationSourceWriter != nil
        let firstRosterCensus = originalAuxiliaryRegistryObservationScope
            == .firstRosterCensus
            && originalAuxiliaryRosterAdmission == nil
            && originalAuxiliaryFirstLeaseCensus == nil
            && preparationWriterPhase == .absent
            && preparationSourceWriter != nil
        let writerTransition = originalAuxiliaryRegistryObservationScope
            == .writerTransition
            && originalAuxiliaryRosterAdmission != nil
            && originalAuxiliaryFirstLeaseCensus != nil
            && originalWriterTransition == nil
            && preparationWriterPhase == .constructing
        let postPointerReproof = originalAuxiliaryRegistryObservationScope
            == .postPointerReproof
            && originalPostPointerReproofInFlight
            && !originalPostPointerReproofUncertain
            && originalAuxiliaryProjectedIntent?.phase == .pointerSwitched
            && preparationWriterPhase == .absent
        let writerPublicationEffect =
            originalAuxiliaryRegistryObservationScope == nil
            && originalWriterTransition?.registry === registry
            && originalWriterTransition?.targetPublicationStarted == true
            && originalWriterTransition?.oldCloseStarted == false
            && originalWriterTransition?.projected == false
            && originalWriterPublicationProjection == nil
            && preparationWriterPhase == .constructing
        let oldWriterCloseEffect =
            originalAuxiliaryRegistryObservationScope == nil
            && originalWriterTransition?.registry === registry
            && originalWriterTransition?.oldCloseStarted == true
            && originalWriterTransition?.projected == false
            && originalWriterPublicationProjection != nil
            && originalOldWriterReleaseProjection == nil
            && preparationWriterPhase == .constructing
        let checkedEffect = originalAuxiliaryRegistryObservationScope == nil
            && (originalAuxiliaryPhaseCASInFlight
                || originalAuxiliarySearchInFlight
                || originalAuxiliaryScratchNoRepairInFlight
                || originalNotificationRootPolicyInFlight
                || originalNotificationMarkerInFlight
                || originalNotificationRemovalInFlight
                || originalAuxiliaryScratchControlPolicyInFlight
                || originalScratchCleanupInFlight
                || originalPointerMutationInFlight != nil
                || originalTargetReaderInFlight
                || originalWriterRecoveryInFlight)
            && originalAuxiliaryRosterAdmission != nil
        guard let router, !detached, !detaching,
              preFirstReaderRecordProbe || firstRosterCensus
                || writerTransition || postPointerReproof
                || writerPublicationEffect
                || oldWriterCloseEffect || checkedEffect,
              !originalAuxiliaryPhaseCASUncertain,
              !originalAuxiliaryRegistryObservationFailed,
              originalExclusion?.registry === registry,
              preparationRegistry === registry,
              originalAuxiliaryRegistryObservations.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        originalAuxiliaryRegistryObservations.append(attempt)
    }

    func recordOriginalEraseAuxiliaryPhaseProjection(
        store: EraseIntentStore,
        expected: EraseIntentV1,
        replacement: EraseIntentV1
    ) throws {
        try requireOriginalEraseAuxiliaryPhaseOwner(store: store,
            expected: expected, replacement: replacement)
        guard let admission = originalAuxiliaryRosterAdmission else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try store.requireOriginalEraseAuxiliaryPublishedRoster(
            admission.receipt)
        guard try store.load() == replacement else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalAuxiliaryProjectedIntent = replacement
    }

    /// Retain the checked Search writer before it can borrow the Support FD.
    /// Its preimage is the immutable original P roster, even though Store and
    /// Registry now have their own projected R control facts.
    func retainOriginalEraseAuxiliarySearchWriter(
        _ writer: OriginalEraseAuxiliarySearchWriterV1,
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard let router, !detached, !detaching,
              originalAuxiliarySearchWriter == nil,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              !originalAuxiliarySearchPublished,
              let first = originalAuxiliaryFirstPhysicalRoster,
              let admission = originalAuxiliaryRosterAdmission,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              preparationCoordinator === coordinator,
              preparationWriterPhase == .installed,
              let session = preparationTargetSession,
              let targetWriter = preparationTargetWriter,
              coordinator.workspaceWriter === targetWriter,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID,
              originalWriterTransition?.projected == true,
              originalExclusion != nil,
              transferredExclusion == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try admission.receipt.requireBound(store: store,
            operation: self, seal: admission.seal)
        try store.requireOriginalEraseAuxiliaryPublishedRoster(
            admission.receipt)
        guard try store.load() == originalAuxiliaryProjectedIntent else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try writer.requireRetained(firstRoster: first,
            supportURL: coordinator.originalEraseAuxiliarySearchSupportURL)
        originalAuxiliarySearchWriter = writer
    }

    func makeOriginalEraseAuxiliarySearchWriter(
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws -> OriginalEraseAuxiliarySearchWriterV1 {
        guard let first = originalAuxiliaryFirstPhysicalRoster else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let writer = try OriginalEraseAuxiliarySearchWriterV1(
            firstRoster: first,
            supportURL: coordinator.originalEraseAuxiliarySearchSupportURL)
        try retainOriginalEraseAuxiliarySearchWriter(writer,
            store: store, coordinator: coordinator)
        return writer
    }

    enum OriginalAuxiliarySearchContinuation {
        case retained(OriginalEraseAuxiliarySearchWriterV1)
        case published(Data)
    }

    /// Retained live retry may continue only this original writer or its
    /// checked publication. Revalidate current Store/roster/session bindings
    /// each time; no failed or uncertain attempt may create a fresh writer.
    func prepareOriginalEraseAuxiliarySearchContinuation(
        expected: EraseIntentV1,
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws -> OriginalAuxiliarySearchContinuation {
        guard let router, !detached, !detaching,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              expected.schemaVersion == 2,
              expected.phase == .sessionActivated,
              originalAuxiliaryProjectedIntent == expected,
              originalAuxiliaryStore === store,
              let first = originalAuxiliaryFirstPhysicalRoster,
              let admission = originalAuxiliaryRosterAdmission,
              admission.seal === originalAuxiliaryRosterSeal,
              preparationCoordinator === coordinator,
              preparationWriterPhase == .installed,
              let session = preparationTargetSession,
              let targetWriter = preparationTargetWriter,
              coordinator.workspaceWriter === targetWriter,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID,
              originalWriterTransition?.projected == true,
              originalExclusion != nil,
              transferredExclusion == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try admission.receipt.requireBound(store: store,
            operation: self, seal: admission.seal)
        try store.requireOriginalEraseAuxiliaryPublishedRoster(admission.receipt)
        guard try store.load() == expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if originalAuxiliarySearchPublished {
            try requireOriginalEraseAuxiliarySearchPublished(
                store: store, coordinator: coordinator)
            guard let bytes = originalAuxiliarySearchWriter?.publishedBytes,
                  bytes == (try LocalSearchIndexStoreV1.originalEraseCanonicalEmptyBytes())
            else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return .published(bytes)
        }
        if let writer = originalAuxiliarySearchWriter {
            try writer.requireRetained(firstRoster: first,
                supportURL: coordinator.originalEraseAuxiliarySearchSupportURL)
            return .retained(writer)
        }
        return .retained(try makeOriginalEraseAuxiliarySearchWriter(
            store: store, coordinator: coordinator))
    }

    /// The checked writer runs synchronously inside the same Search fence and
    /// the retained EX/G. Every failure leaves this operation in-flight or
    /// uncertain; neither the first roster nor an intermediate survivor tree
    /// can be recaptured for a second effect attempt.
    func publishOriginalEraseAuxiliaryEmptySearch(
        writer: OriginalEraseAuxiliarySearchWriterV1,
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator,
        beforeCheckedEffect: (() throws -> Void)? = nil,
        afterCheckedEffect: ((Data) throws -> Void)? = nil
    ) throws -> Data {
        guard let router, !detached, !detaching,
              originalAuxiliarySearchWriter === writer,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              !originalAuxiliarySearchPublished,
              let exclusion = originalExclusion,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              preparationCoordinator === coordinator,
              let target = preparationWriterAllocation?.allocatedHandle,
              preparationWriterPhase == .installed,
              let session = preparationTargetSession,
              let targetWriter = preparationTargetWriter,
              coordinator.workspaceWriter === targetWriter,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID,
              let projected = originalAuxiliaryProjectedIntent,
              projected.phase == .sessionActivated,
              originalAuxiliaryStore === store else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try exclusion.revalidate()
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: target.token)
        let bytes = try LocalSearchIndexStoreV1
            .originalEraseCanonicalEmptyBytes()
        originalAuxiliarySearchInFlight = true
        do {
            try registry
                .withOriginalEraseAuxiliarySearchPublicationUnderRetainedExclusion(
                    activity: activity, operation: self,
                    store: store) {
                    try LocalSearchIndexStoreV1
                        .withOriginalEraseRosteredInvalidation(
                            applicationSupportURL:
                                coordinator.originalEraseAuxiliarySearchSupportURL) {
                            try coordinator
                                .withOriginalEraseAuxiliarySearchSupport(
                                    exclusion: exclusion) { support in
                                try beforeCheckedEffect?()
                                guard try writer.publishEmpty(bytes,
                                    supportFD: support) == bytes else {
                                    throw GenerationLeaseRegistryFailureV1
                                        .uncertainOwner
                                }
                                try writer.requirePublished(bytes,
                                    supportFD: support)
                                try afterCheckedEffect?(bytes)
                            }
                        }
                }
            originalAuxiliarySearchInFlight = false
            originalAuxiliarySearchPublished = true
            return bytes
        } catch {
            originalAuxiliarySearchUncertain = true
            throw error
        }
    }

    /// Registry calls this while holding G both before and after the Search
    /// effect. It uses the frozen pre-effect reader cohort plus the checked
    /// target-writer transition; no recursive Registry read occurs here.
    func requireOriginalEraseAuxiliarySearchPublicationUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, !detached, !detaching,
              originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              originalAuxiliarySearchWriter != nil,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              let coordinator = preparationCoordinator,
              let session = preparationTargetSession,
              let targetWriter = preparationTargetWriter,
              coordinator.workspaceWriter === targetWriter,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let first = originalAuxiliaryFirstLeaseCensus,
              let transition = originalWriterTransition,
              transition.projected,
              transition.prior == (try originalAuxiliaryFirstPlusReaderTokens()),
              let target = transition.targetAllocation.allocatedHandle,
              transition.targetAllocation.preparationPublishedToken
                == target.token,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: target.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        return (transition.prior.filter {
            $0.leaseID != transition.oldWriter.token.leaseID
        } + [target.token]).sorted {
            $0.leaseID.uuidString.lowercased()
                < $1.leaseID.uuidString.lowercased()
        }
    }

    /// One no-create/no-repair Scratch image check while the actual original
    /// owner still holds EX. The checked Registry G scope consumes only the
    /// immutable P image plus its reader/writer/old-close projections. This
    /// admits no Scratch mutation or later cleanup retry.
    func requireOriginalEraseAuxiliaryScratchNoRepairAdmission(
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard !originalAuxiliaryScratchNoRepairAttempted,
              !originalAuxiliaryScratchNoRepairInFlight,
              !originalAuxiliaryScratchNoRepairUncertain,
              originalAuxiliaryStore === store,
              preparationCoordinator === coordinator,
              let exclusion = originalExclusion,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              let transition = originalWriterTransition,
              transition.projected,
              let target = transition.targetAllocation.allocatedHandle,
              let projected = originalOldWriterProjectedSnapshot,
              let first = originalAuxiliaryFirstSnapshot,
              originalAuxiliaryFirstObserver != nil,
              originalAuxiliaryFirstPhysicalRoster != nil,
              originalAuxiliaryRosterAdmission != nil,
              projected.operationsChildren["ScratchDataV1"]
                == first.operationsChildren["ScratchDataV1"],
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchPublished,
              originalAuxiliarySearchWriter == nil,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalAuxiliaryScratchNoRepairAttempted = true
        originalAuxiliaryScratchNoRepairInFlight = true
        do {
            let activity = try exclusion
                .requireOriginalEraseAuxiliaryPhaseActivity(
                    registry: registry, coordinator: coordinator,
                    writer: target.token)
            try coordinator.withOriginalEraseAuxiliarySearchSupport(
                exclusion: exclusion) { support in
                try registry.requireOriginalEraseAuxiliaryScratchNoRepairAdmission(
                    activity: activity, operation: self, store: store,
                    support: support,
                    applicationSupportURL:
                        coordinator.originalEraseAuxiliarySearchSupportURL)
            }
            originalAuxiliaryScratchNoRepairInFlight = false
        } catch {
            originalAuxiliaryScratchNoRepairUncertain = true
            throw error
        }
    }

    /// Pure proof while this operation's actual Registry G is held. No fresh
    /// filesystem observation can become the expected Scratch image.
    func requireOriginalEraseAuxiliaryScratchNoRepairUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore
    ) throws -> (tokens: [GenerationLeaseTokenV1],
        supportFact: String, operationsFact: String,
        operationsNames: [String], scratchFact: String,
        scratchDigest: String) {
        guard let router, !detached, !detaching,
              originalAuxiliaryScratchNoRepairAttempted,
              originalAuxiliaryScratchNoRepairInFlight,
              !originalAuxiliaryScratchNoRepairUncertain,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let transition = originalWriterTransition,
              transition.projected,
              transition.prior
                == (try originalAuxiliaryFirstPlusReaderTokens()),
              let target = transition.targetAllocation.allocatedHandle,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                  registry: registry, activity: activity,
                  writer: target.token),
              let first = originalAuxiliaryFirstSnapshot,
              originalAuxiliaryFirstObserver != nil,
              originalAuxiliaryFirstPhysicalRoster != nil,
              originalAuxiliaryRosterAdmission != nil,
              let projected = originalOldWriterProjectedSnapshot,
              let scratch = projected.operationsChildren["ScratchDataV1"],
              scratch == first.operationsChildren["ScratchDataV1"],
              case .directory(let scratchFact, let scratchDigest) = scratch,
              case .present(let operationsFact, _) = projected.operations,
              Set(projected.operationsChildren.keys)
                == Set(first.operationsChildren.keys),
              originalAuxiliarySearchWriter == nil,
              !originalAuxiliarySearchPublished,
              transition.prior
                == (try originalAuxiliaryFirstPlusReaderTokens()) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        let tokens = (transition.prior.filter {
            $0.leaseID != transition.oldWriter.token.leaseID
        } + [target.token]).sorted {
            $0.leaseID.uuidString.lowercased()
                < $1.leaseID.uuidString.lowercased()
        }
        return (tokens, projected.supportFact, operationsFact,
            projected.operationsChildren.keys.sorted(),
            scratchFact, scratchDigest)
    }

    func failOriginalEraseAuxiliaryScratchNoRepairAdmission() {
        if originalAuxiliaryScratchNoRepairAttempted {
            originalAuxiliaryScratchNoRepairUncertain = true
        }
    }

    /// Admission for a post-writer physical reread through the original
    /// owner's first retained parent descriptors. The caller still has to
    /// prove the stage-specific immutable-first projection.
    func requireOriginalErasePostwriterAuxiliaryParentOwner(
        _ owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        policyPermit: OriginalEraseAuxiliaryScratchControlPolicyPermitV1? = nil,
        notificationPolicyPermit:
            OriginalEraseNotificationRootPolicyPermitV1? = nil,
        notificationMarkerPermit:
            OriginalEraseNotificationMarkerPermitV1? = nil,
        notificationRemovalPermit:
            OriginalEraseNotificationRemovalPermitV1? = nil,
        scratchCleanupScope: OriginalEraseScratchCleanupHeldGScopeV1? = nil
    ) throws {
        guard let router, !detached, !detaching,
              originalAuxiliaryFirstCaptureOwner === owner,
              originalAuxiliaryFirstObserver != nil,
              originalAuxiliaryFirstSnapshot != nil,
              originalAuxiliaryFirstPhysicalRoster != nil,
              originalAuxiliaryRosterAdmission != nil,
              preparationCoordinator === coordinator,
              originalExclusion === exclusion,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              preparationWriterPhase == .installed,
              originalOldWriterReleaseProjection != nil,
              originalOldWriterProjectedSnapshot != nil,
              originalAuxiliarySearchPublished,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        let permits = [policyPermit != nil,
            notificationPolicyPermit != nil,
            notificationMarkerPermit != nil,
            notificationRemovalPermit != nil,
            scratchCleanupScope != nil].filter { $0 }.count
        guard permits <= 1 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let policyPermit {
            try policyPermit.requireHeld()
        } else if let notificationPolicyPermit {
            try notificationPolicyPermit.requireHeld()
        } else if let notificationMarkerPermit {
            try notificationMarkerPermit.requireHeld()
        } else if let notificationRemovalPermit {
            try notificationRemovalPermit.requireHeld()
        } else if let scratchCleanupScope {
            guard originalScratchCleanupScope === scratchCleanupScope,
                  let store = originalAuxiliaryStore,
                  let registry = preparationRegistry,
                  let activity = originalScratchCleanupActivity else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try scratchCleanupScope.requireHeld(operation: self, store: store,
                registry: registry, exclusion: exclusion, activity: activity)
        } else {
            try exclusion.revalidate()
        }
    }

    /// Diagnostic classification of the retained immutable first P image.
    /// It is not an admission or a current filesystem observation.
    var originalEraseNotificationFirstPresenceForDiagnostics:
        OriginalEraseNotificationFirstPresenceV1 {
        guard let first = originalAuxiliaryFirstSnapshot else {
            return .unavailable
        }
        return first.operationsChildren[
            AppLockNotificationControlStoreV1.rootName] == nil
            ? .absent : .present
    }

    /// Settle Notification before its original publisher starts. A present
    /// root remains anchored to immutable P; an absent root requires the
    /// separate checked creation permit and its exact typed projection.
    func settleOriginalEraseNotificationRootPolicy(
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws -> OriginalEraseNotificationRootPolicyReceiptV1 {
        if let receipt = originalNotificationRootPolicyReceipt {
            do {
                return try reproveOriginalEraseNotificationRootPolicy(
                    receipt, store: store, coordinator: coordinator)
            } catch {
                originalNotificationRootPolicyUncertain = true
                throw error
            }
        }
        guard let router, !detached, !detaching,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let observer = originalAuxiliaryFirstObserver,
              let projected = originalOldWriterProjectedSnapshot,
              let roster = originalAuxiliaryFirstPhysicalRoster,
              let searchWriter = originalAuxiliarySearchWriter,
              let searchBytes = searchWriter.publishedBytes,
              originalAuxiliarySearchPublished,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              !originalAuxiliaryNotificationInFlight,
              originalAuxiliaryNotificationReceipt == nil,
              !originalNotificationRootPolicyInFlight,
              !originalNotificationRootPolicyUncertain,
              originalNotificationRootPolicyIO == nil,
              originalNotificationRootPolicyReceipt == nil,
              let exclusion = originalExclusion,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              preparationCoordinator === coordinator,
              let target = preparationWriterAllocation?.allocatedHandle,
              preparationWriterPhase == .installed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try requireOriginalEraseAuxiliarySearchPublished(
            store: store, coordinator: coordinator)
        try exclusion.revalidate()
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: target.token)
        guard let search = roster.record.trees.first(where: {
                  $0.key == "support/\(LocalSearchIndexStoreV1.directoryName)"
              }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let io = EraseAbortCheckedSnapshotIOV1()
        originalNotificationRootPolicyIO = io
        originalNotificationRootPolicyInFlight = true
        do {
            let before = try owner.withOriginalErasePostwriterAuxiliaryParents(
                operation: self, coordinator: coordinator,
                exclusion: exclusion) { support, caches, temporary in
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                let value = try observer.requireOriginalNotificationBefore(
                    oldClose: projected,
                    searchWasAbsent: search.state == "absent",
                    support: support, caches: caches,
                    temporary: temporary)
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                return value
            }
            if before.operationsChildren[AppLockNotificationControlStoreV1.rootName] == nil {
                try observer.requireOriginalNotificationCreationAdmission(before: before)
                originalNotificationRootPolicyBefore = before
                let receipt = try registry.withOriginalEraseNotificationRootPolicy(
                    activity: activity, operation: self, store: store,
                    exclusion: exclusion) { policyPermit in
                    guard !originalNotificationRootCreationInFlight,
                          originalNotificationRootCreationReceipt == nil,
                          originalNotificationRootPolicyBefore == before else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    originalNotificationRootCreationInFlight = true
                    let creationPermit = OriginalEraseNotificationRootCreationPermitV1(
                        operation: self, store: store, registry: registry,
                        exclusion: exclusion, activity: activity,
                        observer: observer, before: before,
                        policyPermit: policyPermit, check: { [self] in
                            guard originalNotificationRootCreationInFlight,
                                  originalNotificationRootCreationReceipt == nil,
                                  originalNotificationRootPolicyBefore == before,
                                  originalNotificationRootPolicyIO === io,
                                  originalAuxiliaryFirstObserver === observer,
                                  originalAuxiliaryFirstCaptureOwner === owner else {
                                throw GenerationLeaseRegistryFailureV1.uncertainOwner
                            }
                            _ = try requireOriginalEraseNotificationRootPolicyUnderHeldG(
                                registry: registry, activity: activity, store: store)
                            try observer.requireOriginalNotificationCreationAdmission(before: before)
                        })
                    defer {
                        creationPermit.revoke()
                        originalNotificationRootCreationInFlight = false
                    }
                    let value = try owner.withOriginalErasePostwriterAuxiliaryParents(
                        operation: self, coordinator: coordinator,
                        exclusion: exclusion, notificationPolicyPermit: policyPermit
                    ) { support, caches, temporary in
                        try io.withOpen(parent: support,
                            name: OwnedStorageRootKindV1.operations.rawValue,
                            flags: O_RDONLY | O_DIRECTORY) { operations in
                            let issued = try ScratchDataLeaseStoreV1.createOriginalEraseNotificationAbsentRoot(
                                applicationSupportURL: coordinator.originalEraseAuxiliarySearchSupportURL,
                                support: support, operations: operations,
                                before: before, observer: observer, retainedIO: io,
                                operation: self, store: store, registry: registry,
                                exclusion: exclusion, activity: activity,
                                permit: creationPermit,
                                reproveOutside: { operationsFact, created, outside in
                                    try searchWriter.requirePublished(searchBytes, supportFD: support)
                                    let digest = try observer.requireOriginalNotificationCreationOutsideRoot(
                                        before: before, operationsFact: operationsFact,
                                        rootIsPresent: created, outsideDigest: outside,
                                        support: support, caches: caches, temporary: temporary)
                                    try searchWriter.requirePublished(searchBytes, supportFD: support)
                                    return digest
                                }, readCreatedPostimage: { operationsFact, fact, digest, stable, disposition in
                                    try searchWriter.requirePublished(searchBytes, supportFD: support)
                                    let observed = try observer.requireOriginalNotificationCreatedPostimage(
                                        before: before, operationsFact: operationsFact,
                                        rootFact: fact, treeDigest: digest, stableDigest: stable,
                                        disposition: disposition,
                                        support: support, caches: caches, temporary: temporary)
                                    try searchWriter.requirePublished(searchBytes, supportFD: support)
                                    return observed
                                })
                            // Preserve the real creation projection even if
                            // this caller-owned Operations close is uncertain.
                            originalNotificationRootCreationReceipt = issued.creationReceipt
                            return issued
                        }
                    }
                    guard let creation = value.creationReceipt,
                          creation.before == before else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    // Retain the actual issued projection before the Registry's
                    // final cohort/readback/unlock can fail. It alone grants no
                    // progress permission while the root-policy owner is in flight.
                    originalNotificationRootCreationReceipt = creation
                    return value
                }
                try receipt.requireBound(operation: self, store: store,
                    registry: registry, exclusion: exclusion, activity: activity)
                guard let creation = receipt.creationReceipt,
                      originalNotificationRootCreationReceipt === creation else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                let final = try owner.withOriginalErasePostwriterAuxiliaryParents(
                    operation: self, coordinator: coordinator, exclusion: exclusion
                ) { support, caches, temporary in
                    try searchWriter.requirePublished(searchBytes, supportFD: support)
                    let value = try observer.requireOriginalNotificationRootPolicyBranches(
                        before: creation.after, allowRootCtime: false,
                        creation: creation, support: support, caches: caches, temporary: temporary)
                    try searchWriter.requirePublished(searchBytes, supportFD: support)
                    return value
                }
                guard final == creation.after,
                      let entry = final.operationsChildren[AppLockNotificationControlStoreV1.rootName],
                      case .directory(let fact, let digest) = entry,
                      receipt.firstRootFact == fact,
                      receipt.projectedRootFact == fact,
                      receipt.firstTreeDigest == digest,
                      receipt.projectedTreeDigest == digest,
                      !receipt.didRequestCompleteProtection else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                originalNotificationRootPolicyBefore = creation.after
                originalNotificationRootPolicyAfter = final
                originalNotificationRootPolicyReceipt = receipt
                originalNotificationRootPolicyInFlight = false
                return receipt
            }
            guard let firstNodes = before.notificationControlNodes,
                  let stable = before.notificationControlStableDigest,
                  let firstRoot = firstNodes.first(where: {
                      $0.path.isEmpty
                  }),
                  case .present(let operationsFact, _) = before.operations,
                  let firstRootEntry = before.operationsChildren[
                      AppLockNotificationControlStoreV1.rootName],
                  case .directory(let firstRootFact, let firstDigest) =
                      firstRootEntry,
                  firstRoot.fullFact == firstRootFact else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            originalNotificationRootPolicyBefore = before
            var projectedAfter:
                EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
            let receipt = try registry.withOriginalEraseNotificationRootPolicy(
                activity: activity, operation: self, store: store,
                exclusion: exclusion) { permit in
                try owner.withOriginalErasePostwriterAuxiliaryParents(
                    operation: self, coordinator: coordinator,
                    exclusion: exclusion,
                    notificationPolicyPermit: permit
                ) { support, caches, temporary in
                    try io.withOpen(parent: support,
                        name: OwnedStorageRootKindV1.operations.rawValue,
                        flags: O_RDONLY | O_DIRECTORY) { operations in
                        let value = try ScratchDataLeaseStoreV1
                            .settleOriginalEraseNotificationExistingRootPolicy(
                                applicationSupportURL:
                                    coordinator.originalEraseAuxiliarySearchSupportURL,
                                support: support, operations: operations,
                                expectedSupportFact: before.supportFact,
                                expectedOperationsFact: operationsFact,
                                expectedOperationsNames:
                                    Array(before.operationsChildren.keys).sorted(),
                                firstControlFact: firstRootFact,
                                firstControlDigest: firstDigest,
                                firstControlNodes: firstNodes,
                                retainedIO: io, operation: self,
                                store: store, registry: registry,
                                exclusion: exclusion, activity: activity,
                                permit: permit,
                                reproveUnchangedBranches: { allowCtime in
                                    try searchWriter.requirePublished(
                                        searchBytes, supportFD: support)
                                    let observed = try observer
                                        .requireOriginalNotificationRootPolicyBranches(
                                            before: before,
                                            allowRootCtime: allowCtime,
                                            support: support, caches: caches,
                                            temporary: temporary)
                                    try searchWriter.requirePublished(
                                        searchBytes, supportFD: support)
                                    if allowCtime {
                                        if let projectedAfter,
                                           projectedAfter != observed {
                                            throw GenerationLeaseRegistryFailureV1
                                                .uncertainOwner
                                        }
                                        projectedAfter = observed
                                    } else if observed != before {
                                        throw GenerationLeaseRegistryFailureV1
                                            .uncertainOwner
                                    }
                                })
                        return value
                    }
                }
            }
            try receipt.requireBound(operation: self, store: store,
                registry: registry, exclusion: exclusion,
                activity: activity)
            let final = try owner.withOriginalErasePostwriterAuxiliaryParents(
                operation: self, coordinator: coordinator,
                exclusion: exclusion) { support, caches, temporary in
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                let value = try observer
                    .requireOriginalNotificationRootPolicyBranches(
                        before: before,
                        allowRootCtime: receipt.didRequestCompleteProtection,
                        support: support, caches: caches,
                        temporary: temporary)
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                return value
            }
            guard let finalEntry = final.operationsChildren[
                    AppLockNotificationControlStoreV1.rootName],
                  case .directory(let finalRootFact, let finalDigest) =
                    finalEntry,
                  let finalRoot = final.notificationControlNodes?
                    .first(where: { $0.path.isEmpty }),
                  finalRoot.fullFact == finalRootFact,
                  finalRootFact == receipt.projectedRootFact,
                  finalDigest == receipt.projectedTreeDigest,
                  final.notificationControlStableDigest == stable,
                  projectedAfter == nil || projectedAfter == final,
                  receipt.firstRootFact == firstRootFact,
                  receipt.firstTreeDigest == firstDigest else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            originalNotificationRootPolicyAfter = final
            originalNotificationRootPolicyReceipt = receipt
            originalNotificationRootPolicyInFlight = false
            return receipt
        } catch {
            originalNotificationRootPolicyUncertain = true
            throw error
        }
    }

    /// Retain the no-repair constructor's checked close owner before any
    /// open, and the returned pinned control before its full binding readback.
    func bindOriginalEraseNotificationControl(
        applicationSupportURL: URL, preferences: PreferencesAdapterV1,
        store: EraseIntentStore, coordinator: StoreSessionCoordinator
    ) throws -> AppLockNotificationControlStoreV1 {
        guard let receipt = originalNotificationRootPolicyReceipt,
              let io = originalNotificationRootPolicyIO,
              let exclusion = originalExclusion,
              let registry = preparationRegistry,
              let target = preparationWriterAllocation?.allocatedHandle else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            _ = try reproveOriginalEraseNotificationRootPolicy(
                receipt, store: store, coordinator: coordinator)
            let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
                registry: registry, coordinator: coordinator, writer: target.token)
            let control: AppLockNotificationControlStoreV1
            if let retained = originalNotificationPreparedControl {
                control = retained
            } else {
                control = try AppLockNotificationControlStoreV1(
                applicationSupportURL: applicationSupportURL, preferences: preferences,
                mustExistForOriginalErase: true,
                originalFirstNotificationPresence: originalEraseNotificationFirstPresenceForDiagnostics,
                    retainedOriginalEraseIO: io)
                originalNotificationPreparedControl = control
            }
            try control.requireOriginalEraseRootPolicyBinding(receipt,
                operation: self, store: store, registry: registry,
                exclusion: exclusion, activity: activity)
            _ = try reproveOriginalEraseNotificationRootPolicy(
                receipt, store: store, coordinator: coordinator)
            return control
        } catch {
            originalNotificationRootPolicyUncertain = true
            throw error
        }
    }

    private func reproveOriginalEraseNotificationRootPolicy(
        _ receipt: OriginalEraseNotificationRootPolicyReceiptV1,
        store: EraseIntentStore, coordinator: StoreSessionCoordinator
    ) throws -> OriginalEraseNotificationRootPolicyReceiptV1 {
        guard !originalNotificationRootPolicyInFlight,
              !originalNotificationRootPolicyUncertain,
              !originalNotificationRootCreationInFlight,
              let io = originalNotificationRootPolicyIO,
              originalNotificationRootPolicyReceipt === receipt,
              originalNotificationRootCreationReceipt === receipt.creationReceipt,
              let before = originalNotificationRootPolicyBefore,
              let after = originalNotificationRootPolicyAfter,
              !originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryNotificationReceipt == nil,
              originalNotificationMarkerReceipt == nil,
              let observer = originalAuxiliaryFirstObserver,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let searchWriter = originalAuxiliarySearchWriter,
              let bytes = searchWriter.publishedBytes,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              preparationCoordinator === coordinator,
              let registry = preparationRegistry,
              let exclusion = originalExclusion, exclusion.registry === registry,
              let target = preparationWriterAllocation?.allocatedHandle,
              preparationWriterPhase == .installed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireOriginalEraseAuxiliarySearchPublished(store: store, coordinator: coordinator)
        try io.requireSettled()
        try exclusion.revalidate()
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator, writer: target.token)
        try receipt.requireBound(operation: self, store: store, registry: registry,
            exclusion: exclusion, activity: activity)
        try owner.withOriginalErasePostwriterAuxiliaryParents(
            operation: self, coordinator: coordinator, exclusion: exclusion
        ) { support, caches, temporary in
            try searchWriter.requirePublished(bytes, supportFD: support)
            let value = try observer.requireOriginalNotificationRootPolicyBranches(
                before: before, allowRootCtime: receipt.didRequestCompleteProtection,
                creation: receipt.creationReceipt,
                support: support, caches: caches, temporary: temporary)
            guard value == after else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try searchWriter.requirePublished(bytes, supportFD: support)
        }
        try io.requireSettled()
        return receipt
    }

    /// A pure admission under the already-held G. It neither observes the
    /// Registry nor reacquires EX, G, or the Notification process fence.
    func requireOriginalEraseNotificationRootPolicyUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, !detached, !detaching,
              originalNotificationRootPolicyInFlight,
              !originalNotificationRootPolicyUncertain,
              originalNotificationRootPolicyIO != nil,
              originalNotificationRootPolicyReceipt == nil,
              originalNotificationRootPolicyBefore != nil,
              !originalAuxiliaryNotificationInFlight,
              originalAuxiliaryNotificationReceipt == nil,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              let coordinator = preparationCoordinator,
              let session = preparationTargetSession,
              let writer = preparationTargetWriter,
              coordinator.workspaceWriter === writer,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let transition = originalWriterTransition,
              transition.projected,
              transition.prior == (try originalAuxiliaryFirstPlusReaderTokens()),
              let target = transition.targetAllocation.allocatedHandle,
              transition.targetAllocation.preparationPublishedToken
                == target.token,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: target.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        return (transition.prior.filter {
            $0.leaseID != transition.oldWriter.token.leaseID
        } + [target.token]).sorted {
            $0.leaseID.uuidString.lowercased()
                < $1.leaseID.uuidString.lowercased()
        }
    }

    func failOriginalEraseNotificationRootPolicy() {
        originalNotificationRootPolicyUncertain = true
    }

    func beginOriginalEraseAuxiliaryNotification(
        control: AppLockNotificationControlStoreV1,
        coordinator: StoreSessionCoordinator,
        store: EraseIntentStore
    ) throws {
        guard originalNotificationPreparedControl === control,
              !originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryNotificationReceipt == nil,
              originalAuxiliaryNotificationBefore == nil,
              originalAuxiliaryNotificationAfter == nil,
              originalAuxiliaryStore === store,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let observer = originalAuxiliaryFirstObserver,
              let projected = originalOldWriterProjectedSnapshot,
              let firstRoster = originalAuxiliaryFirstPhysicalRoster,
              let searchWriter = originalAuxiliarySearchWriter,
              let searchBytes = searchWriter.publishedBytes,
              let policyBefore = originalNotificationRootPolicyBefore,
              let policyAfter = originalNotificationRootPolicyAfter,
              let policyReceipt = originalNotificationRootPolicyReceipt,
              !originalNotificationRootPolicyInFlight,
              !originalNotificationRootPolicyUncertain,
              !originalNotificationMarkerInFlight,
              !originalNotificationMarkerUncertain,
              originalNotificationMarkerReceipt == nil,
              let exclusion = originalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireOriginalEraseAuxiliarySearchPublished(
            store: store, coordinator: coordinator)
        let search = firstRoster.record.trees.first {
            $0.key == "support/\(LocalSearchIndexStoreV1.directoryName)"
        }
        guard let search else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalAuxiliaryNotificationInFlight = true
        originalAuxiliaryNotificationControl = control
        do {
            let before = try owner.withOriginalErasePostwriterAuxiliaryParents(
                operation: self, coordinator: coordinator,
                exclusion: exclusion) { support, caches, temporary in
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                let before = try observer
                    .requireOriginalNotificationRootPolicyBranches(
                        before: policyBefore,
                        allowRootCtime:
                            policyReceipt.didRequestCompleteProtection,
                        creation: policyReceipt.creationReceipt,
                        support: support, caches: caches,
                        temporary: temporary)
                guard before == policyAfter,
                      policyAfter.notificationControlStableDigest
                        == policyBefore.notificationControlStableDigest else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                let outside = try observer
                    .requireOriginalNotificationOutsideRoot(
                        afterPolicy: policyAfter, originalBefore: policyBefore,
                        searchWriter: searchWriter, searchBytes: searchBytes,
                        outsideDigest: nil,
                        creation: policyReceipt.creationReceipt,
                        support: support, caches: caches,
                        temporary: temporary)
                originalNotificationMarkerOutsideDigest = outside
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                return before
            }
            originalAuxiliaryNotificationBefore = before
        } catch {
            originalAuxiliaryNotificationUncertain = true
            throw error
        }
    }

    /// Publish the original marker once, after the separate checked policy
    /// receipt and the before-OS physical image. The workflow invokes this
    /// synchronously inside its Notification transaction fence.
    func publishOriginalEraseAuxiliaryNotificationMarker(
        control: AppLockNotificationControlStoreV1,
        coordinator: StoreSessionCoordinator,
        store: EraseIntentStore
    ) throws -> NotificationEraseRevocationV1 {
        guard let router, !detached, !detaching,
              originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryNotificationControl === control,
              originalAuxiliaryNotificationBefore
                == originalNotificationRootPolicyAfter,
              !originalNotificationMarkerInFlight,
              !originalNotificationMarkerUncertain,
              originalNotificationMarkerReceipt == nil,
              let outsideDigest = originalNotificationMarkerOutsideDigest,
              let policyReceipt = originalNotificationRootPolicyReceipt,
              let policyBefore = originalNotificationRootPolicyBefore,
              let policyAfter = originalNotificationRootPolicyAfter,
              let firstNodes = policyBefore.notificationControlNodes,
              let stableDigest = policyAfter.notificationControlStableDigest,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let observer = originalAuxiliaryFirstObserver,
              let searchWriter = originalAuxiliarySearchWriter,
              let searchBytes = searchWriter.publishedBytes,
              let exclusion = originalExclusion,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              preparationCoordinator === coordinator,
              let target = preparationWriterAllocation?.allocatedHandle,
              preparationWriterPhase == .installed,
              originalAuxiliaryStore === store,
              let intent = originalAuxiliaryProjectedIntent,
              intent.phase == .sessionActivated else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try exclusion.revalidate()
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: target.token)
        try policyReceipt.requireBound(operation: self, store: store,
            registry: registry, exclusion: exclusion, activity: activity)
        let io = EraseAbortCheckedSnapshotIOV1()
        originalNotificationMarkerIO = io
        originalNotificationMarkerInFlight = true
        do {
            let receipt = try registry
                .withOriginalEraseNotificationMarkerPublication(
                    activity: activity, operation: self,
                    store: store, exclusion: exclusion) { permit in
                    try owner.withOriginalErasePostwriterAuxiliaryParents(
                        operation: self, coordinator: coordinator,
                        exclusion: exclusion,
                        notificationMarkerPermit: permit
                    ) { support, caches, temporary in
                        @MainActor func reproveOutside() throws {
                            try searchWriter.requirePublished(searchBytes,
                                supportFD: support)
                            let current = try observer
                                .requireOriginalNotificationOutsideRoot(
                                    afterPolicy: policyAfter, originalBefore: policyBefore,
                                    searchWriter: searchWriter, searchBytes: searchBytes,
                                    outsideDigest: outsideDigest,
                                    creation: originalNotificationRootPolicyReceipt?.creationReceipt,
                                    support: support, caches: caches,
                                    temporary: temporary)
                            guard current == outsideDigest else {
                                throw GenerationLeaseRegistryFailureV1
                                    .uncertainOwner
                            }
                            try searchWriter.requirePublished(searchBytes,
                                supportFD: support)
                        }
                        try reproveOutside()
                        let value = try control
                            .publishOriginalEraseNotificationMarker(
                                operationID: intent.eraseID,
                                operation: self, store: store,
                                registry: registry,
                                exclusion: exclusion,
                                activity: activity,
                                policyReceipt: policyReceipt,
                                firstNodes: firstNodes,
                                firstStableTreeDigest: stableDigest,
                                retainedIO: io, permit: permit,
                                reproveUnaffectedBranches: reproveOutside)
                        try reproveOutside()
                        return value
                    }
                }
            try receipt.requireBound(control: control, operation: self,
                store: store, registry: registry,
                exclusion: exclusion, activity: activity)
            originalNotificationMarkerReceipt = receipt
            originalNotificationMarkerInFlight = false
            return receipt.revocation
        } catch {
            originalNotificationMarkerUncertain = true
            originalAuxiliaryNotificationUncertain = true
            throw error
        }
    }

    func requireOriginalEraseNotificationMarkerControl() throws
        -> AppLockNotificationControlStoreV1 {
        guard originalNotificationMarkerInFlight,
              !originalNotificationMarkerUncertain,
              let control = originalAuxiliaryNotificationControl else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return control
    }

    /// Called by the Registry only with the same activity's G already held.
    func requireOriginalEraseNotificationMarkerUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore
    ) throws -> [GenerationLeaseTokenV1] {
        guard originalNotificationMarkerInFlight,
              !originalNotificationMarkerUncertain,
              originalNotificationMarkerIO != nil,
              originalNotificationMarkerReceipt == nil,
              originalNotificationRootPolicyReceipt != nil,
              originalNotificationRootPolicyAfter != nil,
              originalNotificationMarkerOutsideDigest != nil,
              originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryStore === store else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try requireOriginalEraseNotificationOwnerCohortUnderHeldG(
            registry: registry, activity: activity, store: store)
    }

    private func requireOriginalEraseNotificationOwnerCohortUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore
    ) throws -> [GenerationLeaseTokenV1] {
        guard originalAuxiliaryStore === store else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard let router, !detached, !detaching,
              let coordinator = preparationCoordinator,
              let session = preparationTargetSession,
              let writer = preparationTargetWriter,
              coordinator.workspaceWriter === writer,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let transition = originalWriterTransition,
              transition.projected,
              transition.prior
                == (try originalAuxiliaryFirstPlusReaderTokens()),
              let target = transition.targetAllocation.allocatedHandle,
              transition.targetAllocation.preparationPublishedToken
                == target.token,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: target.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        return (transition.prior.filter {
            $0.leaseID != transition.oldWriter.token.leaseID
        } + [target.token]).sorted {
            $0.leaseID.uuidString.lowercased()
                < $1.leaseID.uuidString.lowercased()
        }
    }

    func failOriginalEraseNotificationMarker() {
        originalNotificationMarkerUncertain = true
        originalAuxiliaryNotificationUncertain = true
    }

    func removeOriginalEraseAuxiliaryNotificationRecords(
        _ absence: OriginalEraseNotificationOSAbsenceReceiptV1,
        control: AppLockNotificationControlStoreV1,
        coordinator: StoreSessionCoordinator,
        store: EraseIntentStore
    ) throws {
        guard let router, !detached, !detaching,
              originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryNotificationControl === control,
              let marker = originalNotificationMarkerReceipt,
              marker.revocation == absence.revocation,
              !originalNotificationMarkerInFlight,
              !originalNotificationMarkerUncertain,
              !originalNotificationRemovalInFlight,
              !originalNotificationRemovalUncertain,
              originalNotificationRemovalReceipt == nil,
              originalNotificationOSAbsence == nil,
              let outsideDigest = originalNotificationMarkerOutsideDigest,
              let policyBefore = originalNotificationRootPolicyBefore,
              let policyAfter = originalNotificationRootPolicyAfter,
              let firstNodes = policyBefore.notificationControlNodes,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let observer = originalAuxiliaryFirstObserver,
              let searchWriter = originalAuxiliarySearchWriter,
              let searchBytes = searchWriter.publishedBytes,
              let exclusion = originalExclusion,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              preparationCoordinator === coordinator,
              let target = preparationWriterAllocation?.allocatedHandle,
              preparationWriterPhase == .installed,
              originalAuxiliaryStore === store else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try absence.requireBound(control: control,
            revocation: marker.revocation)
        try router.requireEraseRetirementOperation(self)
        try exclusion.revalidate()
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: target.token)
        let io = EraseAbortCheckedSnapshotIOV1()
        originalNotificationRemovalIO = io
        originalNotificationOSAbsence = absence
        originalNotificationRemovalInFlight = true
        do {
            let receipt = try registry
                .withOriginalEraseNotificationRecordRemoval(
                    activity: activity, operation: self,
                    store: store, exclusion: exclusion) { permit in
                    try owner.withOriginalErasePostwriterAuxiliaryParents(
                        operation: self, coordinator: coordinator,
                        exclusion: exclusion,
                        notificationRemovalPermit: permit
                    ) { support, caches, temporary in
                        @MainActor func reproveOutside() throws {
                            try searchWriter.requirePublished(searchBytes,
                                supportFD: support)
                            let current = try observer
                                .requireOriginalNotificationOutsideRoot(
                                    afterPolicy: policyAfter, originalBefore: policyBefore,
                                    searchWriter: searchWriter, searchBytes: searchBytes,
                                    outsideDigest: outsideDigest,
                                    creation: originalNotificationRootPolicyReceipt?.creationReceipt,
                                    support: support, caches: caches,
                                    temporary: temporary)
                            guard current == outsideDigest else {
                                throw GenerationLeaseRegistryFailureV1
                                    .uncertainOwner
                            }
                            try searchWriter.requirePublished(searchBytes,
                                supportFD: support)
                        }
                        try reproveOutside()
                        let value = try control
                            .removeOriginalEraseNotificationRecordsAfterOSAbsence(
                                absence, marker: marker,
                                firstNodes: firstNodes,
                                retainedIO: io, permit: permit,
                                reproveUnaffectedBranches: reproveOutside)
                        try reproveOutside()
                        return value
                    }
                }
            try receipt.requireBound(control: control,
                absence: absence, marker: marker)
            originalNotificationRemovalReceipt = receipt
            originalNotificationRemovalInFlight = false
        } catch {
            originalNotificationRemovalUncertain = true
            originalAuxiliaryNotificationUncertain = true
            throw error
        }
    }

    func requireOriginalEraseNotificationRemovalContext() throws -> (
        control: AppLockNotificationControlStoreV1,
        absence: OriginalEraseNotificationOSAbsenceReceiptV1,
        marker: OriginalEraseNotificationMarkerPublicationReceiptV1
    ) {
        guard originalNotificationRemovalInFlight,
              !originalNotificationRemovalUncertain,
              let control = originalAuxiliaryNotificationControl,
              let absence = originalNotificationOSAbsence,
              let marker = originalNotificationMarkerReceipt else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return (control, absence, marker)
    }

    func requireOriginalEraseNotificationRemovalUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore
    ) throws -> [GenerationLeaseTokenV1] {
        guard originalNotificationRemovalInFlight,
              !originalNotificationRemovalUncertain,
              originalNotificationRemovalIO != nil,
              originalNotificationRemovalReceipt == nil,
              originalNotificationOSAbsence != nil,
              originalNotificationMarkerReceipt != nil,
              originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try requireOriginalEraseNotificationOwnerCohortUnderHeldG(
            registry: registry, activity: activity, store: store)
    }

    func failOriginalEraseNotificationRemoval() {
        originalNotificationRemovalUncertain = true
        originalAuxiliaryNotificationUncertain = true
    }

    func observeOriginalEraseAuxiliaryNotificationSuccess(
        _ revocation: NotificationEraseRevocationV1,
        control: AppLockNotificationControlStoreV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryNotificationControl === control,
              !originalNotificationMarkerInFlight,
              !originalNotificationMarkerUncertain,
              let marker = originalNotificationMarkerReceipt,
              marker.revocation == revocation,
              let removal = originalNotificationRemovalReceipt,
              !originalNotificationRemovalInFlight,
              !originalNotificationRemovalUncertain,
              let before = originalAuxiliaryNotificationBefore,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let observer = originalAuxiliaryFirstObserver,
              let searchWriter = originalAuxiliarySearchWriter,
              let searchBytes = searchWriter.publishedBytes,
              let exclusion = originalExclusion,
              originalAuxiliaryNotificationAfter == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            try control.requireNotificationEraseRevocation(revocation)
            let after = try owner.withOriginalErasePostwriterAuxiliaryParents(
                operation: self, coordinator: coordinator,
                exclusion: exclusion) { support, caches, temporary in
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                let after = try observer.requireOriginalNotificationAfter(
                    before: before, revocation: revocation,
                    removal: removal,
                    creation: originalNotificationRootPolicyReceipt?.creationReceipt,
                    support: support, caches: caches,
                    temporary: temporary)
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                return after
            }
            originalAuxiliaryNotificationAfter = after
        } catch {
            originalAuxiliaryNotificationUncertain = true
            throw error
        }
    }

    func finishOriginalEraseAuxiliaryNotification(
        _ receipt: OriginalEraseNotificationEffectReceiptV1,
        control: AppLockNotificationControlStoreV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryNotificationControl === control,
              !originalNotificationMarkerInFlight,
              !originalNotificationMarkerUncertain,
              let marker = originalNotificationMarkerReceipt,
              marker.revocation == receipt.revocation,
              let removal = originalNotificationRemovalReceipt,
              !originalNotificationRemovalInFlight,
              !originalNotificationRemovalUncertain,
              let after = originalAuxiliaryNotificationAfter,
              let before = originalAuxiliaryNotificationBefore,
              let intent = originalAuxiliaryProjectedIntent,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let observer = originalAuxiliaryFirstObserver,
              let searchWriter = originalAuxiliarySearchWriter,
              let searchBytes = searchWriter.publishedBytes,
              let exclusion = originalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            try receipt.requireBound(control: control,
                operationID: intent.eraseID)
            try owner.withOriginalErasePostwriterAuxiliaryParents(
                operation: self, coordinator: coordinator,
                exclusion: exclusion) { support, caches, temporary in
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                let fresh = try observer.requireOriginalNotificationAfter(
                    before: before,
                    revocation: receipt.revocation,
                    removal: removal,
                    creation: originalNotificationRootPolicyReceipt?.creationReceipt,
                    support: support, caches: caches,
                    temporary: temporary)
                try searchWriter.requirePublished(searchBytes,
                    supportFD: support)
                guard fresh == after else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            originalAuxiliaryNotificationReceipt = receipt
            originalAuxiliaryNotificationInFlight = false
        } catch {
            originalAuxiliaryNotificationUncertain = true
            throw error
        }
    }

    /// Retain the completed same-operation notification lineage before the
    /// Router transfers its EX to the retirement proof. This authorizes one
    /// later checked descriptor close after cleanup's last semantic read.
    func makeOriginalEraseNotificationTerminalCloseWitness(
        control: AppLockNotificationControlStoreV1,
        coordinator: StoreSessionCoordinator
    ) throws -> OriginalEraseNotificationTerminalCloseWitnessV1 {
        guard !detached, !detaching,
              preparationCoordinator === coordinator,
              originalAuxiliaryNotificationControl === control,
              !originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              let receipt = originalAuxiliaryNotificationReceipt,
              let marker = originalNotificationMarkerReceipt,
              let removal = originalNotificationRemovalReceipt,
              let absence = originalNotificationOSAbsence,
              let intent = originalAuxiliaryProjectedIntent,
              marker.revocation == receipt.revocation,
              receipt.revocation == absence.revocation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try removal.requireBound(control: control, absence: absence,
            marker: marker)
        try receipt.requireBound(control: control,
            operationID: intent.eraseID)
        return OriginalEraseNotificationTerminalCloseWitnessV1(
            control: control, receipt: receipt, marker: marker,
            removal: removal, absence: absence, eraseID: intent.eraseID)
    }

    func failOriginalEraseAuxiliaryNotification() {
        if originalAuxiliaryNotificationInFlight {
            originalAuxiliaryNotificationUncertain = true
        }
    }

    /// The actual original owner runs the complete fixed Scratch engine
    /// synchronously under its retained EX/activity and this Registry's G.
    /// Only checked engine outcomes can advance the immutable-P projection.
    func eraseOriginalScratchForRetainedOwner(
        store: EraseIntentStore, coordinator: StoreSessionCoordinator
    ) throws -> OriginalEraseScratchCleanupReceiptV1 {
        guard !originalScratchCleanupUncertain,
              !originalScratchCleanupInFlight,
              originalAuxiliaryStore === store,
              preparationCoordinator === coordinator else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if originalAuxiliaryScratchControlPolicyReceipt == nil {
            _ = try settleOriginalEraseAuxiliaryScratchControlPolicy(
                store: store, coordinator: coordinator)
        }
        guard let router, !detached, !detaching,
              !originalAuxiliaryScratchControlPolicyInFlight,
              !originalAuxiliaryScratchControlPolicyUncertain,
              let policy = originalAuxiliaryScratchControlPolicyReceipt,
              let notification = originalAuxiliaryNotificationReceipt,
              let notificationControl = originalAuxiliaryNotificationControl,
              let notificationAfter = originalAuxiliaryNotificationAfter,
              let first = originalAuxiliaryFirstSnapshot,
              let observer = originalAuxiliaryFirstObserver,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let roster = originalAuxiliaryFirstPhysicalRoster,
              let rosterAdmission = originalAuxiliaryRosterAdmission,
              rosterAdmission.seal.canonicalBytes == roster.canonicalBytes,
              let intent = originalAuxiliaryProjectedIntent,
              intent.schemaVersion == 2, intent.phase == .sessionActivated,
              let exclusion = originalExclusion,
              transferredExclusion == nil,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              let target = preparationWriterAllocation?.allocatedHandle,
              preparationWriterPhase == .installed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try notification.requireBound(control: notificationControl,
            operationID: intent.eraseID)
        try requireOriginalEraseAuxiliarySearchPublished(
            store: store, coordinator: coordinator)
        try exclusion.revalidate()
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator, writer: target.token)
        try policy.requireBound(operation: self, store: store, registry: registry,
            exclusion: exclusion, activity: activity)
        let retained = originalScratchCleanupReceipt
        let io: EraseAbortCheckedSnapshotIOV1
        if let old = originalScratchCleanupIO {
            guard retained != nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try old.requireSettled()
            io = old
        } else {
            io = EraseAbortCheckedSnapshotIOV1()
            originalScratchCleanupIO = io // retained BEFORE any child open
        }
        let engineIO: EraseAbortCheckedSnapshotIOV1
        if let old = originalScratchCleanupEngineIO {
            guard retained != nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try old.requireSettled()
            engineIO = old
        } else {
            engineIO = EraseAbortCheckedSnapshotIOV1()
            originalScratchCleanupEngineIO = engineIO
        }
        originalScratchCleanupActivity = activity
        originalScratchCleanupInFlight = true
        do {
            let receipt = try registry.withOriginalEraseScratchCleanupEffect(
                activity: activity, operation: self, store: store,
                exclusion: exclusion) { scope in
                self.originalScratchCleanupScope = scope
                let admission: OriginalEraseScratchCleanupInitialAdmissionV1
                let imageOwner: OriginalEraseScratchCleanupImageOwnerV1
                if let retained {
                    guard let oldAdmission = self.originalScratchCleanupAdmission,
                          let oldOwner = self.originalScratchCleanupImageOwner,
                          self.originalScratchCleanupReceipt === retained else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    admission = oldAdmission
                    imageOwner = oldOwner
                    try admission.renewCompletedObservationScope(scope)
                } else {
                    guard self.originalScratchCleanupAdmission == nil,
                          self.originalScratchCleanupImageOwner == nil,
                          self.originalScratchCleanupPermit == nil else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    admission = OriginalEraseScratchCleanupInitialAdmissionV1(
                        operation: self,
                        applicationSupportURL: coordinator.originalEraseAuxiliarySearchSupportURL,
                        observer: observer, firstSnapshot: first,
                        notificationAfter: notificationAfter,
                        physicalRoster: roster, policyReceipt: policy, scope: scope,
                        store: store, registry: registry, exclusion: exclusion,
                        activity: activity)
                    self.originalScratchCleanupAdmission = admission
                    imageOwner = OriginalEraseScratchCleanupImageOwnerV1(admission: admission)
                    self.originalScratchCleanupImageOwner = imageOwner
                }
                return try owner.withOriginalErasePostwriterAuxiliaryParents(
                    operation: self, coordinator: coordinator, exclusion: exclusion,
                    scratchCleanupScope: scope) { support, caches, temporary in
                    try io.withOpen(parent: support,
                        name: OwnedStorageRootKindV1.operations.rawValue,
                        flags: O_RDONLY | O_DIRECTORY) { operations in
                        if let retained {
                            try retained.requireCheckedSettlement()
                            try imageOwner.requireFinal(retained.finalImage,
                                support: support, caches: caches,
                                temporary: temporary, operations: operations)
                            try retained.requireBound(operation: self, store: store,
                                registry: registry, exclusion: exclusion,
                                activity: activity)
                            return retained
                        }
                        let permit = OriginalEraseScratchCleanupEffectPermitV1(
                            operation: self, store: store, registry: registry,
                            exclusion: exclusion, activity: activity,
                            admission: admission, imageOwner: imageOwner,
                            support: support, caches: caches, temporary: temporary,
                            operations: operations)
                        self.originalScratchCleanupPermit = permit
                        defer { permit.revoke() } // fence BEFORE borrowed Ops close
                        let initial = try imageOwner.captureInitial(support: support,
                            caches: caches, temporary: temporary, operations: operations)
                        try permit.requireInitialImage(initial)
                        let value = try ScratchDataLeaseStoreV1.eraseForOriginalRetainedOwner(
                            applicationSupportURL: admission.applicationSupportURL,
                            operationID: self.operationID, support: support,
                            operations: operations, initialImage: initial,
                            retainedIO: engineIO, permit: permit)
                        try permit.requireFinal(value)
                        return value
                    }
                }
            }
            guard let scope = originalScratchCleanupScope else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try scope.requireCheckedRelease(operation: self, store: store,
                registry: registry, exclusion: exclusion, activity: activity)
            try io.requireSettled()
            try engineIO.requireSettled()
            try receipt.requireCheckedSettlement()
            try receipt.requireBound(operation: self, store: store,
                registry: registry, exclusion: exclusion, activity: activity)
            originalScratchCleanupReceipt = receipt
            originalScratchCleanupInFlight = false
            return receipt
        } catch {
            // Retain request, projection and every uncertain resource. The
            // numeric handles and this effect lane can never be revived.
            failOriginalEraseScratchCleanupEffect()
            throw error
        }
    }

    /// Pure same-owner association check called ONLY by the actual held G
    /// witness. Registry supplies the fresh physical cohort before/after body.
    func requireOriginalEraseScratchCleanupEffectUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, !detached, !detaching,
              originalScratchCleanupInFlight, !originalScratchCleanupUncertain,
              originalScratchCleanupIO != nil,
              originalScratchCleanupEngineIO != nil,
              originalScratchCleanupActivity === activity,
              originalExclusion === exclusion, transferredExclusion == nil,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent?.schemaVersion == 2,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              originalAuxiliaryRosterAdmission != nil,
              originalAuxiliaryFirstPhysicalRoster != nil,
              originalAuxiliaryFirstSnapshot != nil,
              originalAuxiliaryFirstCaptureOwner != nil,
              originalAuxiliaryFirstObserver != nil,
              originalAuxiliarySearchPublished, !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              originalAuxiliarySearchWriter?.publishedBytes != nil,
              !originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryNotificationAfter != nil,
              originalAuxiliaryNotificationReceipt != nil,
              originalNotificationMarkerReceipt != nil,
              originalNotificationRemovalReceipt != nil,
              originalNotificationOSAbsence != nil,
              !originalAuxiliaryScratchControlPolicyInFlight,
              !originalAuxiliaryScratchControlPolicyUncertain,
              let policy = originalAuxiliaryScratchControlPolicyReceipt,
              let coordinator = preparationCoordinator,
              let session = preparationTargetSession,
              let writer = preparationTargetWriter,
              coordinator.workspaceWriter === writer,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID,
              preparationWriterPhase == .installed,
              originalOldWriterReleaseProjection != nil,
              originalOldWriterProjectedSnapshot != nil,
              exclusion.registry === registry, preparationRegistry === registry,
              let transition = originalWriterTransition, transition.projected,
              transition.prior == (try originalAuxiliaryFirstPlusReaderTokens()),
              let target = transition.targetAllocation.allocatedHandle,
              preparationWriterAllocation === transition.targetAllocation,
              transition.targetAllocation.preparationPublishedToken == target.token,
              exclusion.matchesOriginalEraseAuxiliaryPhase(registry: registry,
                activity: activity, writer: target.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try policy.requireBound(operation: self, store: store, registry: registry,
            exclusion: exclusion, activity: activity)
        return (transition.prior.filter {
            $0.leaseID != transition.oldWriter.token.leaseID
        } + [target.token]).sorted {
            $0.leaseID.uuidString.lowercased() < $1.leaseID.uuidString.lowercased()
        }
    }

    fileprivate func requireOriginalEraseScratchCleanupAdmission(
        _ admission: OriginalEraseScratchCleanupInitialAdmissionV1) throws {
        guard originalScratchCleanupAdmission === admission,
              admission.operationID == operationID,
              admission.observer === originalAuxiliaryFirstObserver,
              admission.firstSnapshot == originalAuxiliaryFirstSnapshot,
              admission.notificationAfter == originalAuxiliaryNotificationAfter,
              admission.policyReceipt === originalAuxiliaryScratchControlPolicyReceipt,
              admission.physicalRoster.canonicalBytes == originalAuxiliaryFirstPhysicalRoster?.canonicalBytes,
              let registry = preparationRegistry,
              let activity = originalScratchCleanupActivity,
              let store = originalAuxiliaryStore,
              let exclusion = originalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireOriginalEraseScratchCleanupEffectUnderHeldG(
            registry: registry, activity: activity, store: store, exclusion: exclusion)
    }

    fileprivate func requireOriginalEraseScratchCleanupPermitOrigin(
        _ permit: OriginalEraseScratchCleanupEffectPermitV1) throws {
        guard !detached, !detaching, !originalScratchCleanupUncertain,
              originalScratchCleanupPermit === permit,
              permit.operationID == operationID,
              originalScratchCleanupInFlight || originalScratchCleanupReceipt != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    fileprivate func requireOriginalEraseScratchCleanupPermit(
        _ permit: OriginalEraseScratchCleanupEffectPermitV1) throws {
        try requireOriginalEraseScratchCleanupPermitOrigin(permit)
        guard originalScratchCleanupInFlight, originalScratchCleanupReceipt == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    fileprivate func requireOriginalEraseScratchCleanupPublicationRequest(
        _ intent: OriginalEraseScratchCleanupPrimitiveIntentV1) throws {
        guard let permit = originalScratchCleanupPermit else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try permit.requirePublicationRequest(intent)
    }

    fileprivate func requireOriginalEraseScratchCleanupCanonicalSourceOwnership(
        path: String, fullFact: String
    ) throws {
        guard originalScratchCleanupInFlight, !originalScratchCleanupUncertain,
              let admission = originalScratchCleanupAdmission,
              let imageOwner = originalScratchCleanupImageOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireOriginalEraseScratchCleanupAdmission(admission)
        try imageOwner.requireCanonicalSourceOwnership(path: path, fullFact: fullFact)
        try requireOriginalEraseScratchCleanupAdmission(admission)
    }

    fileprivate func requireOriginalEraseScratchCleanupPrimitiveRequest(
        intent: OriginalEraseScratchCleanupPrimitiveIntentV1,
        outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?
    ) throws {
        guard let permit = originalScratchCleanupPermit else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try permit.requirePrimitiveRequest(intent: intent, outcome: outcome)
    }

    fileprivate func requireOriginalEraseScratchCleanupCatalogFrame(
        attempt: OriginalEraseScratchCleanupAttemptV1,
        session: OriginalEraseScratchCanonicalSourceCatalogSessionV1
    ) throws {
        guard originalScratchCleanupInFlight, !originalScratchCleanupUncertain,
              let permit = originalScratchCleanupPermit else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try permit.requireCatalogFrame(attempt: attempt, session: session)
    }

    fileprivate func requireOriginalEraseScratchCleanupCompletedRenewal(
        _ admission: OriginalEraseScratchCleanupInitialAdmissionV1,
        scope: OriginalEraseScratchCleanupHeldGScopeV1) throws {
        guard originalScratchCleanupAdmission === admission,
              originalScratchCleanupScope === scope,
              let receipt = originalScratchCleanupReceipt,
              let registry = preparationRegistry,
              let activity = originalScratchCleanupActivity,
              let store = originalAuxiliaryStore,
              let exclusion = originalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try receipt.requireCheckedSettlement()
        try scope.requireHeld(operation: self, store: store, registry: registry,
            exclusion: exclusion, activity: activity)
    }

    func failOriginalEraseScratchCleanupEffect() {
        originalScratchCleanupUncertain = true
    }

    /// The notification OS-success receipt and the first-P roster authorize
    /// one existing ingress-control root policy transition. This does not
    /// authorize the later ordinary ingress or Scratch deletion effects.
    func settleOriginalEraseAuxiliaryScratchControlPolicy(
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws -> OriginalEraseScratchControlPolicyReceiptV1 {
        guard let router, !detached, !detaching,
              !originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              let notification = originalAuxiliaryNotificationReceipt,
              let control = originalAuxiliaryNotificationControl,
              let after = originalAuxiliaryNotificationAfter,
              let first = originalAuxiliaryFirstSnapshot,
              first.ingressControlNodes == after.ingressControlNodes,
              let observer = originalAuxiliaryFirstObserver,
              let owner = originalAuxiliaryFirstCaptureOwner,
              originalAuxiliaryFirstPhysicalRoster != nil,
              originalAuxiliaryRosterAdmission != nil,
              originalAuxiliarySearchPublished,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              !originalAuxiliaryScratchControlPolicyInFlight,
              !originalAuxiliaryScratchControlPolicyUncertain,
              originalAuxiliaryScratchControlPolicyIO == nil,
              originalAuxiliaryScratchControlPolicyReceipt == nil,
              let exclusion = originalExclusion,
              let registry = preparationRegistry,
              registry === exclusion.registry,
              preparationCoordinator === coordinator,
              originalAuxiliaryStore === store,
              let projectedIntent = originalAuxiliaryProjectedIntent,
              projectedIntent.phase == .sessionActivated,
              let target = preparationWriterAllocation?.allocatedHandle,
              preparationWriterPhase == .installed,
              let session = preparationTargetSession,
              let writer = preparationTargetWriter,
              coordinator.workspaceWriter === writer,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try notification.requireBound(control: control,
            operationID: projectedIntent.eraseID)
        try requireOriginalEraseAuxiliarySearchPublished(
            store: store, coordinator: coordinator)
        try exclusion.revalidate()
        let activity = try exclusion.requireOriginalEraseAuxiliaryPhaseActivity(
            registry: registry, coordinator: coordinator,
            writer: target.token)
        guard case .present(let operationsFact, _) = after.operations else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let controlName = "ProtectedIngressReceiptsV1"
        let firstControlFact: String?
        let firstControlDigest: String?
        if let child = after.operationsChildren[controlName] {
            guard case .directory(let fact, let digest) = child else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            firstControlFact = fact
            firstControlDigest = digest
        } else {
            firstControlFact = nil
            firstControlDigest = nil
        }
        let expectedNames = Array(after.operationsChildren.keys).sorted()
        let io = EraseAbortCheckedSnapshotIOV1()
        originalAuxiliaryScratchControlPolicyIO = io
        originalAuxiliaryScratchControlPolicyInFlight = true
        do {
            let receipt = try registry
                .withOriginalEraseAuxiliaryScratchControlPolicy(
                    activity: activity, operation: self, store: store,
                    exclusion: exclusion) { permit in
                try owner.withOriginalErasePostwriterAuxiliaryParents(
                    operation: self, coordinator: coordinator,
                    exclusion: exclusion, policyPermit: permit
                ) { support, caches, temporary in
                    try io.withOpen(parent: support,
                        name: OwnedStorageRootKindV1.operations.rawValue,
                        flags: O_RDONLY | O_DIRECTORY) { operations in
                        func fullFact(_ value: stat) -> String {
                            "\(value.st_dev)|\(value.st_ino)|\(value.st_mode)|\(value.st_uid)|\(value.st_gid)|\(value.st_nlink)|\(value.st_size)|\(value.st_mtimespec.tv_sec)|\(value.st_mtimespec.tv_nsec)|\(value.st_ctimespec.tv_sec)|\(value.st_ctimespec.tv_nsec)"
                        }
                        func requireOperations() throws {
                            var held = stat(), named = stat()
                            guard Darwin.fstat(operations, &held) == 0,
                                  Darwin.fstatat(support,
                                      OwnedStorageRootKindV1.operations.rawValue,
                                      &named, AT_SYMLINK_NOFOLLOW) == 0,
                                  fullFact(held) == operationsFact,
                                  fullFact(named) == operationsFact,
                                  try io.names(in: operations) == expectedNames else {
                                throw GenerationLeaseRegistryFailureV1
                                    .uncertainOwner
                            }
                        }
                        try requireOperations()
                        let value = try ScratchDataLeaseStoreV1
                            .settleOriginalEraseAuxiliaryExistingControlPolicy(
                                applicationSupportURL:
                                    coordinator.originalEraseAuxiliarySearchSupportURL,
                                support: support, operations: operations,
                                expectedSupportFact: after.supportFact,
                                expectedOperationsFact: operationsFact,
                                expectedOperationsNames: expectedNames,
                                firstControlFact: firstControlFact,
                                firstControlDigest: firstControlDigest,
                                firstControlNodes: after.ingressControlNodes,
                                retainedIO: io, operation: self,
                                store: store, registry: registry,
                                exclusion: exclusion, activity: activity,
                                permit: permit,
                                reproveUnchangedBranches: {
                                    try observer
                                        .requireOriginalScratchControlPolicyUnaffectedBranches(
                                            notificationAfter: after,
                                            support: support, caches: caches,
                                            temporary: temporary)
                                })
                        try requireOperations()
                        return value
                    }
                }
            }
            try receipt.requireBound(operation: self, store: store,
                registry: registry, exclusion: exclusion,
                activity: activity)
            try io.requireSettled()
            originalAuxiliaryScratchControlPolicyReceipt = receipt
            originalAuxiliaryScratchControlPolicyInFlight = false
            return receipt
        } catch {
            originalAuxiliaryScratchControlPolicyUncertain = true
            throw error
        }
    }

    /// Called only while the Registry's distinct checked G is actually held.
    /// No filesystem observation or recursive Registry acquisition occurs.
    func requireOriginalEraseAuxiliaryScratchControlPolicyUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        store: EraseIntentStore
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, !detached, !detaching,
              originalAuxiliaryScratchControlPolicyInFlight,
              !originalAuxiliaryScratchControlPolicyUncertain,
              originalAuxiliaryScratchControlPolicyIO != nil,
              originalAuxiliaryScratchControlPolicyReceipt == nil,
              !originalAuxiliaryNotificationInFlight,
              !originalAuxiliaryNotificationUncertain,
              originalAuxiliaryNotificationReceipt != nil,
              originalAuxiliaryNotificationAfter != nil,
              originalAuxiliaryStore === store,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              let coordinator = preparationCoordinator,
              let session = preparationTargetSession,
              let writer = preparationTargetWriter,
              coordinator.workspaceWriter === writer,
              coordinator.modelContext === session.modelContext,
              coordinator.generationID == session.generationID,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              preparationRegistry === registry,
              let transition = originalWriterTransition,
              transition.projected,
              transition.prior == (try originalAuxiliaryFirstPlusReaderTokens()),
              let target = transition.targetAllocation.allocatedHandle,
              transition.targetAllocation.preparationPublishedToken
                == target.token,
              exclusion.matchesOriginalEraseAuxiliaryPhase(
                registry: registry, activity: activity,
                writer: target.token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        return (transition.prior.filter {
            $0.leaseID != transition.oldWriter.token.leaseID
        } + [target.token]).sorted {
            $0.leaseID.uuidString.lowercased()
                < $1.leaseID.uuidString.lowercased()
        }
    }

    func failOriginalEraseAuxiliaryScratchControlPolicy() {
        originalAuxiliaryScratchControlPolicyUncertain = true
    }

    /// Downstream auxiliary stages can demand the same checked empty bytes
    /// and projected physical Search tree; the first P image is never reset.
    func requireOriginalEraseAuxiliarySearchPublished(
        store: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard let router, !detached, !detaching,
              originalAuxiliarySearchPublished,
              !originalAuxiliarySearchInFlight,
              !originalAuxiliarySearchUncertain,
              let writer = originalAuxiliarySearchWriter,
              let bytes = writer.publishedBytes,
              originalAuxiliaryStore === store,
              preparationCoordinator === coordinator,
              originalAuxiliaryProjectedIntent?.phase == .sessionActivated,
              let exclusion = originalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try exclusion.revalidate()
        try coordinator.withOriginalEraseAuxiliarySearchSupport(
            exclusion: exclusion) { support in
            try writer.requirePublished(bytes, supportFD: support)
        }
    }

    func requireOriginalErasePublishedAuxiliaryActivationOwner(
        session: StoreGenerationSession,
        factory: StoreGenerationFactory,
        coordinator: StoreSessionCoordinator
    ) throws -> StoreTemporalNormalizationExclusionV1 {
        guard let admission = originalAuxiliaryRosterAdmission,
              admission.seal === originalAuxiliaryRosterSeal,
              originalAuxiliaryFirstIntent?.schemaVersion == 2,
              originalAuxiliaryFirstIntent?.phase
                == .emptyGenerationPrepared,
              originalAuxiliaryStore != nil,
              let exclusion = originalExclusion,
              transferredExclusion == nil,
              preparationWriterPhase == .absent,
              preparationWriterAllocation == nil,
              originalTargetReaderHandle != nil,
              originalTargetReaderProjection != nil,
              originalTargetReaderProjectedSnapshot != nil,
              !originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              preparationCoordinator === coordinator else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requirePreparationWriterConstruction(session: session,
            factory: factory, coordinator: coordinator)
        try exclusion.revalidate()
        return exclusion
    }

    func registerPreparationRegistry(_ registry: GenerationLeaseRegistryV1,
        factory: StoreGenerationFactory, inventory: EraseReaderRetirementInventoryV1) throws {
        guard let router, preparationServiceFrame, inventory === self.inventory,
              let configured = preparationFactory, configured.sharesRegistryProvider(with: factory),
              preparationRegistry == nil || preparationRegistry === registry,
              preparationFailureWitness == nil, !detached else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireEraseRetirementOperation(self)
        preparationRegistry = registry
    }

    func requirePreparationReaderAllocation(_ attempt: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1) throws {
        guard let router, preparationServiceFrame, preparationRegistry === registry,
              inventory.containsPreparationAllocation(attempt), attempt.matches(registry: registry),
              preparationFailureWitness == nil, !detached else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireEraseRetirementOperation(self)
    }

    func requirePreparationLeaseCensus(_ leases: [GenerationLeaseTokenV1],
        registry: GenerationLeaseRegistryV1) throws {
        guard let router, preparationServiceFrame, preparationRegistry === registry,
              let source = preparationSourceWriter, preparationWriterPhase != .installing,
              preparationFailureWitness == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        if preparationWriterPhase == .installed {
            guard let target = preparationWriterAllocation?.allocatedHandle,
                  let coordinator = preparationCoordinator, let writer = preparationTargetWriter,
                  let session = preparationTargetSession,
                  coordinator.workspaceWriter === writer, coordinator.modelContext === session.modelContext,
                  coordinator.generationID == session.generationID else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            // Genuine recovery may construct a target reader after the fixed
            // installation. The actual installed writer replaces the closed
            // original in this census; it is not counted a second time.
            try inventory.requirePreparationCensus(leases, registry: registry,
                sourceWriter: target, writer: nil)
        } else {
            try inventory.requirePreparationCensus(leases, registry: registry,
                sourceWriter: source, writer: preparationWriterAllocation)
        }
    }

    /// Called outside Registry G, after the complete original auxiliary
    /// roster has been durably published and before the target publication
    /// attempt takes G. Retain the exact first cohort, including every reader;
    /// later held-G calls may compare it but may never recapture it.
    func beginOriginalEraseWriterTransition(
        registry: GenerationLeaseRegistryV1,
        oldWriter: GenerationLeaseHandleV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard let router, originalAuxiliaryRosterAdmission != nil,
              originalWriterTransition == nil, !detached, !detaching,
              originalAuxiliaryRegistryObservationScope == nil,
              !originalAuxiliaryRegistryObservationFailed,
              originalExclusion != nil, transferredExclusion == nil,
              preparationCoordinator === coordinator,
              preparationRegistry === registry,
              preparationSourceWriter === oldWriter,
              preparationWriterAllocation === targetAllocation,
              preparationWriterPhase == .constructing,
              targetAllocation.matches(registry: registry),
              targetAllocation.preparationPublishedToken == nil,
              preparationFailureWitness == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        guard let exclusion = originalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try exclusion.revalidate()
        let activity = try exclusion.requireOriginalEraseWriterTransitionActivity(
            registry: registry, oldWriter: oldWriter, coordinator: coordinator)
        originalAuxiliaryRegistryObservationScope = .writerTransition
        do {
            let prior = try registry.observeOriginalEraseAuxiliaryRegistryChecked(
                activity: activity, operation: self)
            let expected = try originalAuxiliaryFirstPlusReaderTokens()
            guard prior == expected,
                  let reader = originalTargetReaderHandle else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try inventory.requirePreparationCensus(prior.filter {
                    $0.leaseID != reader.token.leaseID
                }, registry: registry,
                sourceWriter: oldWriter, writer: targetAllocation)
            guard prior.filter({ $0.role == .writer }) == [oldWriter.token],
                  Set(prior.map(\.leaseID)).count == prior.count else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            originalWriterTransition = OriginalWriterTransition(registry: registry,
                activity: activity, oldWriter: oldWriter,
                targetAllocation: targetAllocation, prior: prior,
                targetPublicationStarted: true, oldCloseStarted: false,
                projected: false)
            originalAuxiliaryRegistryObservationScope = nil
        } catch {
            originalAuxiliaryRegistryObservationFailed = true
            originalAuxiliaryRegistryObservationScope = nil
            throw error
        }
    }

    /// Pure immutable cohort projection. The reader effect already checked
    /// the exact prior and prior-plus-own Registry states under G, and its
    /// physical Operations receipt was rewalked through the first held
    /// auxiliary owner before a writer transition can consume this array.
    private func originalAuxiliaryFirstPlusReaderTokens()
        throws -> [GenerationLeaseTokenV1] {
        guard let first = originalAuxiliaryFirstLeaseCensus,
              let handle = originalTargetReaderHandle,
              let allocation = originalTargetReaderAllocation,
              let projection = originalTargetReaderProjection,
              originalTargetReaderProjectedSnapshot != nil,
              !originalTargetReaderInFlight,
              !originalTargetReaderUncertain,
              allocation.allocatedHandle === handle,
              allocation.originalEraseRetainedPublishedToken
                == handle.token,
              projection.checkedSettled,
              projection.priorTokens == first,
              projection.publishedToken == handle.token,
              !first.contains(where: {
                $0.leaseID == handle.token.leaseID
              }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let expected = (first + [handle.token]).sorted {
            $0.leaseID.uuidString.lowercased()
                < $1.leaseID.uuidString.lowercased()
        }
        guard projection.afterTokens == expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return expected
    }

    /// Pure actual-G preeffect proof for the target-writer record/temp. The
    /// reader's checked physical after-image is the only admissible source;
    /// a current named Operations tree cannot establish its own baseline.
    func requireOriginalEraseWriterFirstOperationsUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        operationsFact: String,
        operationsDigest: String,
        leaseRootFact: String,
        leaseDigest: String
    ) throws {
        guard let router, !detached, !detaching,
              let transition = originalWriterTransition,
              transition.registry === registry,
              transition.activity === activity,
              transition.targetPublicationStarted,
              !transition.oldCloseStarted, !transition.projected,
              transition.targetAllocation.preparationPublishedToken == nil,
              originalWriterPublicationProjection == nil,
              !originalWriterProjectionUncertain,
              let reader = originalTargetReaderProjection,
              originalTargetReaderProjectedSnapshot != nil,
              operationsFact == reader.operationsFact,
              operationsDigest == reader.afterOperationsDigest,
              leaseRootFact == reader.afterLeaseRootFact,
              leaseDigest == reader.afterLeaseDigest,
              transition.prior == (try originalAuxiliaryFirstPlusReaderTokens()),
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              exclusion.matchesOriginalEraseWriterTransition(
                registry: registry, activity: activity,
                oldWriter: transition.oldWriter) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
    }

    /// Pure actual-G preeffect proof for removing only the old writer. The
    /// dual-writer checked receipt must already have been rewalked against
    /// the immutable first auxiliary image outside G.
    func requireOriginalEraseOldWriterCloseFirstOperationsUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        operationsFact: String,
        operationsDigest: String,
        leaseRootFact: String,
        leaseDigest: String
    ) throws {
        guard let router, !detached, !detaching,
              let transition = originalWriterTransition,
              transition.registry === registry,
              transition.activity === activity,
              transition.oldCloseStarted, !transition.projected,
              originalWriterProjectedSnapshot != nil,
              !originalWriterProjectionUncertain,
              originalOldWriterReleaseProjection == nil,
              !originalOldWriterProjectionUncertain,
              let writer = originalWriterPublicationProjection,
              operationsFact == writer.operationsFact,
              operationsDigest == writer.afterOperationsDigest,
              leaseRootFact == writer.afterLeaseRootFact,
              leaseDigest == writer.afterLeaseDigest,
              let exclusion = originalExclusion,
              exclusion.registry === registry,
              exclusion.matchesOriginalEraseWriterTransition(
                registry: registry, activity: activity,
                oldWriter: transition.oldWriter) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
    }

    /// Pure operation/owner proof for a Registry caller that already holds G.
    /// It never observes Registry, calls exclusion.revalidate, or opens a new
    /// lease. The Registry itself compares its locked complete census to the
    /// returned immutable prior plus the one operation-owned target token.
    func requireOriginalEraseWriterTransitionUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        oldWriter: GenerationLeaseHandleV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        stage: EraseOriginalWriterTransitionStageV1
    ) throws -> [GenerationLeaseTokenV1] {
        guard let router, originalAuxiliaryRosterAdmission != nil,
              let transition = originalWriterTransition,
              transition.registry === registry, transition.activity === activity,
              transition.oldWriter === oldWriter,
              transition.targetAllocation === targetAllocation,
              transition.targetPublicationStarted, !transition.projected,
              !originalWriterRecoveryUncertain,
              preparationRegistry === registry,
              preparationSourceWriter === oldWriter,
              preparationWriterAllocation === targetAllocation,
              preparationFailureWitness == nil,
              let exclusion = originalExclusion,
              exclusion.matchesOriginalEraseWriterTransition(
                registry: registry, activity: activity, oldWriter: oldWriter),
              !detached, !detaching else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        let targetToken = targetAllocation.preparationPublishedToken
        switch stage {
        case .beforeTarget:
            guard !transition.oldCloseStarted, targetToken == nil,
                  preparationWriterPhase == .constructing else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        case .oldAndTarget:
            guard !transition.oldCloseStarted, targetToken != nil,
                  targetAllocation.allocatedHandle?.token == targetToken,
                  preparationWriterPhase == .constructing else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        case .afterOld:
            guard transition.oldCloseStarted, targetToken != nil,
                  targetAllocation.allocatedHandle?.token == targetToken,
                  preparationWriterPhase == .constructing else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        return transition.prior
    }

    /// One synchronous target-journal recovery under the original retained
    /// EX and the already published dual-writer cohort. This never mints a
    /// writer or turns a failed recovery into a fresh allocation.
    func beginOriginalEraseWriterRecovery(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1
    ) throws {
        guard let router, !detached, !detaching,
              !originalWriterRecoveryInFlight,
              !originalWriterRecoveryUncertain,
              !originalWriterRecoveryCompleted,
              let transition = originalWriterTransition,
              transition.registry === registry,
              transition.activity === activity,
              transition.targetAllocation === targetAllocation,
              transition.targetPublicationStarted,
              !transition.oldCloseStarted, !transition.projected,
              targetAllocation.allocatedHandle === targetHandle,
              originalWriterPublicationProjection != nil,
              originalWriterProjectedSnapshot != nil,
              !originalWriterProjectionUncertain,
              preparationWriterPhase == .constructing else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        originalWriterRecoveryInFlight = true
    }

    func requireOriginalEraseWriterRecoveryUnderHeldG(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1
    ) throws -> [GenerationLeaseTokenV1] {
        guard originalWriterRecoveryInFlight,
              !originalWriterRecoveryUncertain,
              targetAllocation.allocatedHandle === targetHandle,
              let transition = originalWriterTransition else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try requireOriginalEraseWriterTransitionUnderHeldG(
            registry: registry, activity: activity,
            oldWriter: transition.oldWriter,
            targetAllocation: targetAllocation, stage: .oldAndTarget)
    }

    func finishOriginalEraseWriterRecovery(
        _ receipt: OriginalEraseRetainedWriterRecoveryReceiptV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1
    ) throws {
        guard originalWriterRecoveryInFlight,
              !originalWriterRecoveryUncertain,
              !originalWriterRecoveryCompleted,
              originalWriterTransition?.registry === registry,
              originalWriterTransition?.activity === activity,
              originalWriterTransition?.targetAllocation === targetAllocation,
              targetAllocation.allocatedHandle === targetHandle else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try receipt.requireBound(registry: registry, operation: self,
            activity: activity, targetAllocation: targetAllocation,
            targetHandle: targetHandle)
        originalWriterRecoveryInFlight = false
        originalWriterRecoveryCompleted = true
    }

    func failOriginalEraseWriterRecovery() {
        originalWriterRecoveryUncertain = true
    }

    func beginOriginalEraseSourceWriterClose(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        targetAllocation: GenerationWriterAllocationAttemptV1
    ) throws {
        guard var transition = originalWriterTransition,
              transition.registry === registry,
              transition.activity === activity,
              transition.targetAllocation === targetAllocation,
              !transition.oldCloseStarted, !transition.projected,
              originalWriterRecoveryCompleted,
              !originalWriterRecoveryInFlight,
              !originalWriterRecoveryUncertain,
              originalWriterPublicationProjection != nil,
              originalWriterProjectedSnapshot != nil,
              !originalWriterProjectionUncertain,
              let target = targetAllocation.allocatedHandle,
              target.token == targetAllocation.preparationPublishedToken else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try target.requireLiveTemporalIdentity(mutationRegistry: registry)
        transition.oldCloseStarted = true
        originalWriterTransition = transition
    }

    func retainOriginalEraseWriterPublicationProjection(
        _ projection: OriginalEraseRetainedWriterPublicationProjectionV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1
    ) throws {
        guard let transition = originalWriterTransition,
              transition.targetAllocation === targetAllocation,
              !transition.oldCloseStarted, !transition.projected,
              targetAllocation.allocatedHandle === targetHandle,
              targetAllocation.originalEraseRetainedWriterPublicationProjection
                === projection,
              originalWriterPublicationProjection == nil,
              originalWriterProjectedSnapshot == nil,
              !originalWriterProjectionUncertain,
              let reader = originalTargetReaderProjection,
              originalTargetReaderProjectedSnapshot != nil,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let coordinator = preparationCoordinator,
              let exclusion = originalExclusion else {
            originalWriterProjectionUncertain = true
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            try projection.requireBound(registry: transition.registry,
                operation: self, oldWriter: transition.oldWriter,
                targetAllocation: targetAllocation,
                targetHandle: targetHandle)
            guard projection.priorTokens == transition.prior,
                  projection.afterTokens == (transition.prior
                    + [targetHandle.token]).sorted(by: {
                        $0.leaseID.uuidString.lowercased()
                            < $1.leaseID.uuidString.lowercased()
                    }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            originalWriterPublicationProjection = projection
            originalWriterProjectedSnapshot = try owner
                .requireOriginalWriterProjected(reader: reader,
                    writer: projection,
                    targetAllocation: targetAllocation,
                    targetHandle: targetHandle, operation: self,
                    coordinator: coordinator, exclusion: exclusion)
        } catch {
            originalWriterProjectionUncertain = true
            throw error
        }
    }

    func requireOriginalEraseWriterProjectionOwner(
        _ projection: OriginalEraseRetainedWriterPublicationProjectionV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1,
        owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard let router, !detached, !detaching,
              let transition = originalWriterTransition,
              transition.targetAllocation === targetAllocation,
              transition.registry === exclusion.registry,
              !transition.oldCloseStarted, !transition.projected,
              targetAllocation.allocatedHandle === targetHandle,
              originalWriterPublicationProjection === projection,
              originalWriterProjectedSnapshot == nil,
              !originalWriterProjectionUncertain,
              originalAuxiliaryFirstCaptureOwner === owner,
              preparationCoordinator === coordinator,
              originalExclusion === exclusion,
              let reader = originalTargetReaderProjection,
              originalTargetReaderProjectedSnapshot != nil,
              projection.firstOperationsDigest
                == reader.afterOperationsDigest,
              projection.firstLeaseRootFact
                == reader.afterLeaseRootFact,
              projection.firstLeaseDigest == reader.afterLeaseDigest,
              projection.checkedSettled else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try projection.requireBound(registry: transition.registry,
            operation: self, oldWriter: transition.oldWriter,
            targetAllocation: targetAllocation,
            targetHandle: targetHandle)
    }

    func retainOriginalEraseOldWriterReleaseProjection(
        _ projection: OriginalEraseRetainedOldWriterReleaseProjectionV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1
    ) throws {
        guard let transition = originalWriterTransition,
              transition.targetAllocation === targetAllocation,
              transition.oldCloseStarted, !transition.projected,
              targetAllocation.allocatedHandle === targetHandle,
              targetAllocation.originalEraseRetainedOldWriterReleaseProjection
                === projection,
              originalOldWriterReleaseProjection == nil,
              originalOldWriterProjectedSnapshot == nil,
              !originalOldWriterProjectionUncertain,
              let reader = originalTargetReaderProjection,
              let writer = originalWriterPublicationProjection,
              originalWriterProjectedSnapshot != nil,
              let owner = originalAuxiliaryFirstCaptureOwner,
              let coordinator = preparationCoordinator,
              let exclusion = originalExclusion else {
            originalOldWriterProjectionUncertain = true
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            try projection.requireBound(registry: transition.registry,
                operation: self, oldWriter: transition.oldWriter,
                targetAllocation: targetAllocation,
                targetHandle: targetHandle)
            guard projection.priorTokens == writer.afterTokens,
                  projection.afterTokens == writer.afterTokens.filter({
                    $0.leaseID != transition.oldWriter.token.leaseID
                  }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            originalOldWriterReleaseProjection = projection
            originalOldWriterProjectedSnapshot = try owner
                .requireOriginalOldWriterCloseProjected(reader: reader,
                    writer: writer, release: projection,
                    targetAllocation: targetAllocation,
                    targetHandle: targetHandle, operation: self,
                    coordinator: coordinator, exclusion: exclusion)
        } catch {
            originalOldWriterProjectionUncertain = true
            throw error
        }
    }

    func requireOriginalEraseOldWriterCloseProjectionOwner(
        _ projection: OriginalEraseRetainedOldWriterReleaseProjectionV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1,
        owner: StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard let router, !detached, !detaching,
              let transition = originalWriterTransition,
              transition.targetAllocation === targetAllocation,
              transition.registry === exclusion.registry,
              transition.oldCloseStarted, !transition.projected,
              targetAllocation.allocatedHandle === targetHandle,
              originalOldWriterReleaseProjection === projection,
              originalOldWriterProjectedSnapshot == nil,
              !originalOldWriterProjectionUncertain,
              originalAuxiliaryFirstCaptureOwner === owner,
              preparationCoordinator === coordinator,
              originalExclusion === exclusion,
              let writer = originalWriterPublicationProjection,
              originalWriterProjectedSnapshot != nil,
              projection.firstOperationsDigest
                == writer.afterOperationsDigest,
              projection.firstLeaseRootFact
                == writer.afterLeaseRootFact,
              projection.firstLeaseDigest == writer.afterLeaseDigest,
              projection.checkedSettled else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try projection.requireBound(registry: transition.registry,
            operation: self, oldWriter: transition.oldWriter,
            targetAllocation: targetAllocation,
            targetHandle: targetHandle)
    }

    func requireCompletedOriginalEraseWriterTransition(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        targetAllocation: GenerationWriterAllocationAttemptV1
    ) throws {
        guard let transition = originalWriterTransition,
              transition.registry === registry,
              transition.activity === activity,
              transition.targetAllocation === targetAllocation,
              transition.oldCloseStarted, !transition.projected,
              originalOldWriterReleaseProjection != nil,
              originalOldWriterProjectedSnapshot != nil,
              !originalOldWriterProjectionUncertain,
              targetAllocation.allocatedHandle?.token
                == targetAllocation.preparationPublishedToken else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try transition.oldWriter.requireClosedForOriginalEraseWriterTransition(registry: registry)
    }

    func recordOriginalEraseWriterTransitionProjected(
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        targetAllocation: GenerationWriterAllocationAttemptV1
    ) throws {
        try requireCompletedOriginalEraseWriterTransition(registry: registry,
            activity: activity, targetAllocation: targetAllocation)
        guard var transition = originalWriterTransition else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        transition.projected = true
        originalWriterTransition = transition
    }

    func requirePreparationWriterConstruction(session: StoreGenerationSession,
        factory: StoreGenerationFactory, coordinator: StoreSessionCoordinator) throws {
        guard let router, preparationServiceFrame, preparationCoordinator === coordinator,
              let configured = preparationFactory, configured.sharesRegistryProvider(with: factory),
              inventory.observesPreparationSession(session), preparationFailureWitness == nil,
              preparationWriterPhase == .absent || preparationWriterPhase == .constructing,
              preparationTargetSession == nil || preparationTargetSession === session else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireErasePreparationTarget(self, session: session, coordinator: coordinator)
    }

    func retainPreparationWriterAllocation(_ attempt: GenerationWriterAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1, session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator) throws {
        guard let factory = preparationFactory else { throw AppAccessContractFailureV1.staleAttempt }
        try requirePreparationWriterConstruction(session: session, factory: factory, coordinator: coordinator)
        guard preparationWriterPhase == .absent, preparationWriterAllocation == nil,
              preparationRegistry === registry, attempt.matches(registry: registry),
              session.generationEpoch == attempt.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        preparationTargetSession = session
        preparationTargetRootURL = session.generationRootURL.standardizedFileURL
        preparationWriterAllocation = attempt
        preparationWriterPhase = .constructing
    }

    func requirePreparationWriterAllocation(_ attempt: GenerationWriterAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1) throws {
        guard let router, preparationServiceFrame, preparationRegistry === registry,
              preparationWriterAllocation === attempt, attempt.matches(registry: registry),
              preparationWriterPhase == .constructing, preparationFailureWitness == nil,
              let session = preparationTargetSession, let coordinator = preparationCoordinator else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        // This guard runs inside Registry G as well as outside it. It checks
        // original Router ownership and the captured target, never opens a
        // pointer/registry authority recursively under the allocation lock.
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
        guard session.generationEpoch == attempt.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func observePreparationWriter(_ writer: WorkspaceWriterV1,
        allocation: GenerationWriterAllocationAttemptV1) throws {
        guard preparationServiceFrame, preparationWriterPhase == .constructing,
              preparationWriterAllocation === allocation, preparationTargetWriter == nil,
              allocation.allocatedHandle != nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        preparationTargetWriter = writer
    }

    func beginPreparationWriterInstallation(allocation: GenerationWriterAllocationAttemptV1,
        coordinator: StoreSessionCoordinator) throws {
        guard let session = preparationTargetSession, let factory = preparationFactory else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requirePreparationWriterConstruction(session: session, factory: factory, coordinator: coordinator)
        guard preparationWriterPhase == .constructing, preparationWriterAllocation === allocation,
              preparationTargetWriter != nil, allocation.allocatedHandle != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        preparationWriterPhase = .installing
    }

    func requirePreparationInstalledAssociation(allocation: GenerationWriterAllocationAttemptV1,
        coordinator: StoreSessionCoordinator, writer: WorkspaceWriterV1,
        session: StoreGenerationSession, factory: StoreGenerationFactory) throws {
        guard let router, preparationServiceFrame, preparationWriterAllocation === allocation,
              preparationCoordinator === coordinator, preparationTargetWriter === writer,
              preparationTargetSession === session, let configured = preparationFactory,
              configured.sharesRegistryProvider(with: factory),
              preparationWriterPhase == .installing || preparationWriterPhase == .installed else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireErasePreparationTarget(self, session: session, coordinator: coordinator)
    }

    func recordPreparationWriterInstalled(_ attempt: GenerationWriterAllocationAttemptV1,
        coordinator: StoreSessionCoordinator) throws {
        guard preparationWriterAllocation === attempt else { throw AppAccessContractFailureV1.staleAttempt }
        try coordinator.requireErasePreparationInstalled(attempt, operation: self)
        preparationWriterPhase = .installed
    }

    func requirePreparationFailureWitnessRegistration(inventory: EraseReaderRetirementInventoryV1,
        registry: GenerationLeaseRegistryV1, writer: GenerationWriterAllocationAttemptV1?) throws {
        guard let router, inventory === self.inventory, preparationRegistry === registry,
              preparationWriterAllocation === writer, preparationFailureWitness == nil,
              !preparationServiceFrame, preparationWriterPhase != .installing,
              preparationWriterPhase != .installed, !detached, prepared == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
    }

    func disposeFailedPreparationAllocations() throws {
        guard let router, !preparationServiceFrame, !detached, prepared == nil,
              preparationWriterPhase != .installing, preparationWriterPhase != .installed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        guard let registry = preparationRegistry else {
            try inventory.requireNoConstructedResourcesForAbort()
            return
        }
        if preparationFailureWitness == nil {
            preparationFailureWitness = try inventory.sealForPreparationFailure(operation: self,
                registry: registry, writer: preparationWriterAllocation)
        }
        guard let preparationFailureWitness else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try preparationFailureWitness.disposeOwnedAllocations()
    }

    func requireFailedPreparationDisposed() throws {
        guard !preparationServiceFrame else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard let preparationFailureWitness else {
            guard preparationRegistry == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try inventory.requireNoConstructedResourcesForAbort()
            return
        }
        try preparationFailureWitness.requireDisposed()
    }

    func requirePreparationFailureDisposal(witness: ErasePreparationFailureDrainWitnessV1,
        registry: GenerationLeaseRegistryV1) throws {
        guard let router, preparationFailureWitness === witness, preparationRegistry === registry,
              !preparationServiceFrame, preparationTargetSession == nil,
              preparationTargetWriter == nil, preparationWriterPhase != .installing,
              preparationWriterPhase != .installed, !detached, prepared == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
#if DEBUG
        if completedAbortInventoryBindingInProgress {
            try router.requireCompletedAbortInventoryBindingOperation(self)
            return
        }
#endif
        try router.requireEraseRetirementOperation(self)
    }

#if DEBUG
    fileprivate func poisonInterruptedOriginalPreparation(
        sourceGenerationID: UUID, targetGenerationID: UUID,
        completedAbort: Bool = false
    ) throws {
        guard originalShutdownState == .active, !detached, !detaching,
              prepared == nil, drain == nil, originalExclusion == nil,
              transferredExclusion == nil, !startedExclusionAcquisition,
              !preparationServiceFrame, preparationWriterPhase != .installing,
              preparationSourceWriter != nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        // A genuine pre-intent rollback retains its exact preparation-failure
        // witness after checked disposal. The original owner may be poisoned
        // only while that retained witness still proves every allocation closed.
        try requireNoRetirementResourcesForAbort()
        originalShutdownSourceGenerationID = sourceGenerationID
        originalShutdownTargetGenerationID = targetGenerationID
        originalShutdownState = .poisoned
        if completedAbort {
            try armCompletedAbortOriginalShutdownInventory()
        }
    }

    /// The already-disposed preparation witness is verified while this exact
    /// original Router operation is still current. The later original-shutdown
    /// seal can then include its live original readers without reopening
    /// inventory admission or minting an unrelated witness.
    private func armCompletedAbortOriginalShutdownInventory() throws {
        guard originalShutdownState == .poisoned,
              !preparationServiceFrame,
              let router,
              let coordinator = preparationCoordinator else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireCompletedAbortInventoryBindingOperation(self)
        let control = try coordinator.captureOriginalEraseShutdownControl(
            operation: self)
        guard !control.installed,
              preparationRegistry == nil || preparationRegistry === control.registry,
              preparationSourceWriter === control.writer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard !completedAbortInventoryBindingInProgress else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        completedAbortInventoryBindingInProgress = true
        defer { completedAbortInventoryBindingInProgress = false }
        try inventory.armCompletedAbortOriginalShutdownAfterDisposal(
            operation: self, registry: control.registry,
            witness: preparationFailureWitness,
            writer: preparationWriterAllocation)
    }

    /// Durable pre-detach interruption keeps its constructed readers and
    /// possibly its installed target writer for the original-shutdown witness.
    /// No-effect abort disposal is deliberately a separate authority.
    fileprivate func poisonInterruptedDurableOriginalPreparation(
        sourceGenerationID: UUID, targetGenerationID: UUID,
        expectedFault: EraseAllFailurePoint,
        retainedExclusion: StoreTemporalNormalizationExclusionV1? = nil
    ) throws {
        let exclusionCutIsOwned: Bool
        if let retainedExclusion {
            exclusionCutIsOwned = originalExclusion === retainedExclusion
                && startedExclusionAcquisition
                && transferredExclusion == nil
                && (originalWriterTransition.map({ $0.projected }) ?? true)
                && expectedFault != .afterPreparedWrite
        } else {
            exclusionCutIsOwned = originalExclusion == nil
                && !startedExclusionAcquisition
                && transferredExclusion == nil
        }
        guard originalShutdownState == .active, !detached, !detaching,
              prepared == nil, drain == nil, exclusionCutIsOwned,
              !preparationServiceFrame, preparationFailureWitness == nil,
              let router, let registry = preparationRegistry,
              let source = preparationSourceWriter,
              source.token.ownerID == registry.ownerID,
              preparationFactory != nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        switch expectedFault {
        case .afterPreparedWrite, .beforePointerSwitch,
             .afterPointerSwitch, .beforePointerPhaseWrite,
             .afterPointerPhaseWrite, .beforeSessionActivation:
            guard preparationWriterPhase == .absent else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        case .afterSessionActivation, .beforeSessionPhaseWrite,
             .afterSessionPhaseWrite, .beforeCleanup:
            guard preparationWriterPhase == .installed,
                  preparationWriterAllocation?.allocatedHandle != nil,
                  preparationTargetSession != nil,
                  preparationTargetWriter != nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        default:
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireEraseRetirementOperation(self)
        try retainedExclusion?.revalidate()
        // sealForOriginalShutdown repeats the full registered owner census
        // before any EX transfer. This edge only forbids further effects.
        originalShutdownSourceGenerationID = sourceGenerationID
        originalShutdownTargetGenerationID = targetGenerationID
        originalShutdownState = .poisoned
    }

    fileprivate func retainedOriginalExclusionForDurableShutdown()
        throws -> StoreTemporalNormalizationExclusionV1? {
        guard !startedExclusionAcquisition || originalExclusion != nil,
              transferredExclusion == nil,
              originalWriterTransition.map({ $0.projected }) ?? true else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return originalExclusion
    }

    /// The actual original Service has already proved its notification
    /// revocation/readback refusal with the retained frame and durable intent.
    /// This separate branch preserves the source writer's checked release and
    /// carries the original EX through target-installed cold shutdown.
    fileprivate func poisonInterruptedNotificationRefusalWithRetainedExclusion(
        sourceGenerationID: UUID,
        targetGenerationID: UUID,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard let router, originalShutdownState == .active,
              !detached, !detaching, prepared == nil, drain == nil,
              originalExclusion === exclusion,
              startedExclusionAcquisition,
              transferredExclusion == nil,
              originalWriterTransition?.projected == true,
              !preparationServiceFrame,
              preparationFailureWitness == nil,
              preparationCoordinator === coordinator,
              preparationWriterPhase == .installed,
              preparationWriterAllocation?.allocatedHandle != nil,
              preparationTargetSession != nil,
              preparationTargetSession?.generationID == targetGenerationID,
              preparationTargetWriter != nil,
              let registry = preparationRegistry,
              preparationSourceWriter?.token.ownerID == registry.ownerID,
              preparationSourceWriter?.token.epoch.generationID
                == sourceGenerationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEraseRetirementOperation(self)
        try exclusion.revalidate()
        originalShutdownSourceGenerationID = sourceGenerationID
        originalShutdownTargetGenerationID = targetGenerationID
        originalShutdownState = .poisoned
    }

    fileprivate func requirePreactivationDurableShutdownAssociation(
        coordinator: StoreSessionCoordinator,
        sourceGenerationID: UUID, targetGenerationID: UUID,
        poisoned: Bool
    ) throws {
        guard !detached, !detaching, prepared == nil,
              preparationCoordinator === coordinator,
              !preparationServiceFrame,
              let registry = preparationRegistry,
              let source = preparationSourceWriter,
              source.token.ownerID == registry.ownerID,
              preparationFactory != nil,
              preparationFailureWitness == nil,
              preparationWriterPhase == .absent,
              preparationWriterAllocation == nil,
              preparationTargetSession == nil,
              preparationTargetWriter == nil else {
            // Fixed DEBUG category only; the original guard remains the
            // authority and still throws before any effect or suspension.
            let firstFailure: String
            if detached || detaching || prepared != nil {
                firstFailure = "shape"
            } else if !(preparationCoordinator === coordinator) {
                firstFailure = "coordinator"
            } else if preparationServiceFrame {
                firstFailure = "service-frame"
            } else if preparationRegistry == nil {
                firstFailure = "registry"
            } else if preparationSourceWriter == nil {
                firstFailure = "source-writer"
            } else if let registry = preparationRegistry,
                      let source = preparationSourceWriter,
                      source.token.ownerID != registry.ownerID {
                firstFailure = "registry-owner"
            } else if preparationFactory == nil {
                firstFailure = "factory"
            } else if preparationFailureWitness != nil {
                firstFailure = "failure-witness"
            } else if preparationWriterPhase != .absent {
                firstFailure = "writer-phase"
            } else if preparationWriterAllocation != nil {
                firstFailure = "writer-allocation"
            } else if preparationTargetSession != nil {
                firstFailure = "target-session"
            } else if preparationTargetWriter != nil {
                firstFailure = "target-writer"
            } else {
                firstFailure = "changed-during-check"
            }
            FileHandle.standardError.write(Data((
                "V23_ERASE_PREACTIVATION_ASSOCIATION_V1 first=" + firstFailure + "\n"
            ).utf8))
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if poisoned {
            guard originalShutdownState == .poisoned,
                  originalShutdownSourceGenerationID == sourceGenerationID,
                  originalShutdownTargetGenerationID == targetGenerationID else {
                FileHandle.standardError.write(Data(
                    "V23_ERASE_PREACTIVATION_ASSOCIATION_V1 first=shutdown-state\n".utf8))
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        } else {
            guard originalShutdownState == .active else {
                FileHandle.standardError.write(Data(
                    "V23_ERASE_PREACTIVATION_ASSOCIATION_V1 first=shutdown-state\n".utf8))
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
    }

    func requireOriginalShutdownCoordinatorAssociation(
        coordinator: StoreSessionCoordinator, registry: GenerationLeaseRegistryV1,
        writerHandle: GenerationLeaseHandleV1, writer: WorkspaceWriterV1,
        session: StoreGenerationSession,
        installedAllocation: GenerationWriterAllocationAttemptV1?,
        installedOperation: EraseRouterOperationV1?,
        factory: StoreGenerationFactory
    ) throws {
        guard originalShutdownState == .poisoned,
              preparationCoordinator === coordinator,
              !preparationServiceFrame,
              preparationRegistry == nil || preparationRegistry === registry,
              let source = preparationSourceWriter,
              source.token.ownerID == registry.ownerID,
              let configured = preparationFactory,
              configured.sharesRegistryProvider(with: factory) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        switch preparationWriterPhase {
        case .absent, .constructing:
            guard installedAllocation == nil, installedOperation == nil,
                  writerHandle === source,
                  session.generationID == originalShutdownSourceGenerationID else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try source.requireLiveTemporalIdentity(mutationRegistry: registry)
        case .installed:
            guard installedOperation === self,
                  let allocation = preparationWriterAllocation,
                  installedAllocation === allocation,
                  let targetHandle = allocation.allocatedHandle,
                  targetHandle === writerHandle,
                  preparationTargetWriter === writer,
                  preparationTargetSession === session,
                  session.generationID == originalShutdownTargetGenerationID,
                  session.generationEpoch == allocation.generationEpoch,
                  session.generationRootURL.standardizedFileURL == preparationTargetRootURL,
                  allocation.matches(registry: registry) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try source.requireCheckedClosedForOriginalEraseShutdown(registry: registry)
        case .installing:
            // The source close may have attempted an ambiguous descriptor
            // release before target assignment. No cold proof is possible.
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireOriginalShutdownInventoryRegistration(
        inventory value: EraseReaderRetirementInventoryV1,
        registry: GenerationLeaseRegistryV1,
        writer: GenerationWriterAllocationAttemptV1?
    ) throws {
        guard originalShutdownState == .poisoned,
              value === inventory, originalShutdownWitness == nil,
              !preparationServiceFrame, !detached, prepared == nil,
              preparationWriterPhase != .installing,
              preparationRegistry == nil || preparationRegistry === registry,
              preparationWriterAllocation === writer,
              preparationSourceWriter?.token.ownerID == registry.ownerID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireOriginalShutdownWitness(
        _ witness: EraseOriginalShutdownWitnessV1,
        registry: GenerationLeaseRegistryV1
    ) throws {
        guard originalShutdownWitness === witness,
              originalShutdownRegistry === registry,
              originalShutdownState == .poisoned
                || originalShutdownState == .controlsTransferred else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireCompletedAbortExclusiveScratchOwner(
        witness: EraseOriginalShutdownWitnessV1,
        registry: GenerationLeaseRegistryV1,
        root: StoreTemporalPhysicalRootExclusionV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        try requireOriginalShutdownWitness(witness, registry: registry)
        guard originalShutdownState == .controlsTransferred,
              originalShutdownRoot === root,
              !completedAbortExclusiveScratchUncertain,
              let router else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireCompletedAbortPreAliasSealForExclusiveScratch(
            self, receipt: receipt)
    }

    private var completedAbortExclusiveScratchUncertain = false

    func poisonCompletedAbortExclusiveScratchOwner() {
        completedAbortExclusiveScratchUncertain = true
    }

    fileprivate func retainOriginalShutdownActivity(
        _ activity: GenerationTemporalActivityHandleV1,
        registry: GenerationLeaseRegistryV1
    ) throws {
        // Retain first: even a mismatched or duplicate acquisition cannot
        // disappear through an unchecked EX descriptor deinit.
        guard originalShutdownActivity == nil else {
            originalShutdownUncertainActivities.append(activity)
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalShutdownActivity = activity
        guard originalShutdownState == .poisoned,
              originalShutdownRegistry === registry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    fileprivate func retainOriginalShutdownRoot(
        _ root: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        guard originalShutdownRoot == nil else {
            originalShutdownUncertainRoots.append(root)
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalShutdownRoot = root
        guard originalShutdownState == .poisoned,
              originalShutdownActivity != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// Checked DEBUG transition from this operation's already-retained EX to
    /// the original shutdown witness. The Coordinator receipt is formed only
    /// after all producers are drained and its current writer is exact. Both
    /// handles remain retained by `originalExclusion` if any proof throws.
    fileprivate func retainOriginalShutdownExistingExclusion(
        _ control: StoreOriginalEraseRetainedExclusionShutdownControlV1
    ) throws {
        guard originalShutdownState == .poisoned,
              originalShutdownWitness != nil,
              originalShutdownRegistry === control.registry,
              originalShutdownCurrentWriter === control.writer,
              originalShutdownInstalled == control.installed,
              originalShutdownActivity == nil,
              originalShutdownRoot == nil,
              originalExclusion === control.exclusion,
              preparationCoordinator === control.coordinator,
              preparationRegistry === control.registry,
              transferredExclusion == nil,
              originalWriterTransition.map({ $0.projected }) ?? true else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // No new descriptor or lock is acquired. Retain the exact same two
        // owners before Registry's fallible under-G shutdown census.
        originalShutdownActivity = control.activity
        originalShutdownRoot = control.physicalRoot
    }

    func requireOriginalShutdownRetainedExclusionDetachment(
        _ control: StoreOriginalEraseRetainedExclusionShutdownControlV1,
        registryReceipt: OriginalEraseRetainedExclusionShutdownRegistryReceiptV1
    ) throws -> EraseOriginalShutdownWitnessV1 {
        guard originalShutdownState == .controlsTransferred,
              let witness = originalShutdownWitness,
              witness === registryReceipt.witness,
              originalShutdownRegistry === control.registry,
              originalShutdownActivity === control.activity,
              originalShutdownRoot === control.physicalRoot,
              originalShutdownCurrentWriter === control.writer,
              originalShutdownInstalled == control.installed,
              originalExclusion === control.exclusion,
              preparationCoordinator === control.coordinator,
              preparationRegistry === control.registry,
              transferredExclusion == nil,
              originalWriterTransition.map({ $0.projected }) ?? true else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try witness.requireBound(registry: control.registry)
        return witness
    }

    fileprivate func detachOriginalShutdownRetainedExclusion(
        _ control: StoreOriginalEraseRetainedExclusionShutdownControlV1,
        registryReceipt: OriginalEraseRetainedExclusionShutdownRegistryReceiptV1
    ) throws {
        try control.coordinator.detachRetainedOriginalEraseShutdownControl(
            control, registryReceipt: registryReceipt, operation: self)
        // The Coordinator has already severed both strong owner links. There
        // is no fallible edge after this assignment; the Router keeps the
        // exact activity and Support EX until checked shutdown completes.
        originalExclusion = nil
    }

    fileprivate func prepareOriginalShutdownControls(
        registry: GenerationLeaseRegistryV1,
        writer: GenerationLeaseHandleV1,
        installed: Bool
    ) throws -> EraseOriginalShutdownWitnessV1 {
        guard originalShutdownState == .poisoned,
              originalShutdownWitness == nil,
              originalShutdownRegistry == nil,
              preparationSourceWriter != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalShutdownRegistry = registry
        originalShutdownCurrentWriter = writer
        originalShutdownInstalled = installed
        let witness = try inventory.sealForOriginalShutdown(
            operation: self, registry: registry, writer: preparationWriterAllocation)
        originalShutdownWitness = witness
        return witness
    }

    fileprivate func markOriginalShutdownControlsTransferred() throws {
        guard originalShutdownState == .poisoned,
              originalShutdownActivity != nil, originalShutdownRoot != nil,
              originalShutdownWitness != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalShutdownState = .controlsTransferred
    }

    fileprivate func finishInterruptedOriginalPreparationForColdRestart(
        finalNoEffect: (() throws -> Void)? = nil
    ) throws {
        guard originalShutdownState == .controlsTransferred,
              let witness = originalShutdownWitness,
              let registry = originalShutdownRegistry,
              let activity = originalShutdownActivity,
              let root = originalShutdownRoot,
              let source = preparationSourceWriter,
              let current = originalShutdownCurrentWriter else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Weak aliases are live observations, not a time-based or cached bit.
        // A refusal here is harmless and retryable after the caller lets go.
        do {
            try witness.requireDrained(registry: registry)
        } catch {
            FileHandle.standardError.write(Data(
                "ERASE_ORIGINAL_SHUTDOWN_V1 stage=alias-drain-before\n".utf8))
            throw error
        }
        var diagnosticStage = "preparation-reader-close"
        do {
            for reader in witness.preparationReaders {
                try reader.closeForOriginalEraseShutdown(proof: witness, activity: activity)
            }
            diagnosticStage = "captured-reader-close"
            for reader in witness.capturedReaders {
                try witness.requireCapturedReader(reader, registry: registry)
                try reader.closeForOriginalEraseShutdown(witness: witness, activity: activity)
            }
            diagnosticStage = "target-writer-close"
            if let target = witness.preparationWriter {
                try target.closeForOriginalEraseShutdown(proof: witness, activity: activity)
            }
            diagnosticStage = "source-writer-close"
            if originalShutdownInstalled {
                try source.requireCheckedClosedForOriginalEraseShutdown(registry: registry)
                guard witness.preparationWriter?.allocatedHandle === current else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            } else {
                guard current === source else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
                try source.closeForOriginalEraseShutdown(witness: witness, activity: activity)
            }
            diagnosticStage = "alias-drain-after"
            try witness.requireDrained(registry: registry)
            diagnosticStage = "lease-census"
            try registry.requireOriginalEraseShutdownLeaseCensus(witness: witness,
                activity: activity)
            diagnosticStage = "v949-sqlite-postclose"
            if let armed = v949PostHandoffSource {
                try armed.service.completeV949OwnedSourceCloseTransitionForTesting(
                    armed.binding, operation: self)
            }
            diagnosticStage = "final-no-effect"
            try finalNoEffect?()
            diagnosticStage = "exclusion-close"
            try registry.closeOriginalEraseShutdownExclusion(
                witness: witness, activity: activity, physicalRoot: root)
            diagnosticStage = "guard-unlink"
            try registry.unlinkOriginalEraseShutdownOwnerGuard(witness: witness)
            diagnosticStage = "guard-unlinked-finish"
            try registry.finishOriginalEraseShutdownUnlinkedGuard(witness: witness)
            originalShutdownState = .controlsReleased
        } catch {
            // Any ambiguous close or post-unlink result remains terminal and
            // retains the exact owner. This path cannot mint cold readiness.
            originalShutdownState = .uncertain
            FileHandle.standardError.write(Data((
                "ERASE_ORIGINAL_SHUTDOWN_V1 stage=" + diagnosticStage + "\n"
            ).utf8))
            throw error
        }
    }

    fileprivate func finishCompletedAbortForColdRestart(
        service: EraseAllService,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard !completedAbortExclusiveScratchUncertain,
              let registry = originalShutdownRegistry,
              let witness = originalShutdownWitness,
              let root = originalShutdownRoot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try finishInterruptedOriginalPreparationForColdRestart {
            try registry.withCompletedAbortExclusiveScratchPermit(
                witness: witness, physicalRoot: root,
                service: service, operation: self, receipt: receipt) { permit in
                try service.requireCompletedAbortPostCloseNoEffectForTesting(
                    operation: self, receipt: receipt, permit: permit)
            }
        }
    }

    /// Reprove the immutable original source while the authentic Router still
    /// holds EX/G and AppAccess still holds its internal source aliases. This
    /// stores no session, context, container, or new reader owner.
    fileprivate func requireCompletedAbortPreAliasNoEffect(
        service: EraseAllService,
        receipt: AbortedEraseAdmissionReceiptV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard originalShutdownState == .controlsTransferred,
              let registry = originalShutdownRegistry,
              let witness = originalShutdownWitness,
              originalShutdownActivity != nil, originalShutdownRoot != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try registry.sealCompletedAbortCanonicalUnderOriginalShutdown(
            witness: witness, service: service, operation: self,
            receipt: receipt, coordinator: coordinator)
    }
#endif

    var hasPreparedCleanup: Bool { prepared != nil }

#if DEBUG
    /// The old source reader must be the wrapper captured by this exact
    /// original operation. The prepared path uses its transferred EX owner;
    /// the interrupted pre-detach path uses its retained preparation Registry.
    func requireCapturedOriginalReaderActiveForV949Fixture(
        session: StoreGenerationSession
    ) throws {
        guard let registry = preparationRegistry,
              let token = session.readerLeaseToken,
              token.role == .reader,
              token.epoch.generationID == session.generationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let reader = try inventory.capturedOriginalReaderForV949Fixture(
            session: session, operation: self, registry: registry,
            sealedDrain: detached ? drain : nil)
        if detached {
            guard let exclusion = transferredExclusion,
                  let prepared, let binding,
                  prepared.binding == binding,
                  session.generationID != binding.subject.newGenerationID else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try exclusion.requireCapturedOriginalReaderActiveForV949Fixture(
                session: session, reader: reader)
        } else {
            guard let router, !detaching, prepared == nil,
                  originalShutdownState == .active else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            try router.requireEraseRetirementOperation(self)
            try registry.requireCapturedOriginalReaderActiveForV949Fixture(reader)
        }
    }

    func requirePublishedTargetForV949Fixture() throws -> UUID {
        guard detached, let prepared else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return try prepared.requirePublishedTargetForV949Fixture()
    }
#endif

    func requireLiveExecution(coordinator: StoreSessionCoordinator) throws {
        guard let router, !detached else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireLiveEraseService(self, coordinator: coordinator)
    }

    func captureOriginalC05Producer(
        coordinator: StoreSessionCoordinator
    ) throws -> Bool {
        try requireLiveExecution(coordinator: coordinator)
        let runner = try coordinator.captureOriginalC05RunnerForErase(
            operationID: ticket.operationID)
        // Keep the concrete actor before any next fallible check or await.
        originalC05Runner = runner
        try requireLiveExecution(coordinator: coordinator)
        return runner != nil
    }

    func requireOriginalC05CapturedEpoch(
        coordinator: StoreSessionCoordinator
    ) throws -> GenerationEpochV1 {
        try requireLiveExecution(coordinator: coordinator)
        return try coordinator.requireOriginalC05CapturedEpoch(
            operationID: ticket.operationID)
    }

    /// The UUID is an identity argument for the checked private-copy scratch.
    /// It is not a ticket or an effect permit; the retained owner checks the
    /// original operation and EX/G before opening any source bytes.
    var originalRecoveryPrivateCopyOperationID: UUID { ticket.operationID }

    /// The original ticket's already acknowledged subject selects the
    /// source-writer pre-open path without reading a reparative journal or
    /// constructing a new Registry provider.
    func originalRecoverySubjectBeforeOpening(
        coordinator: StoreSessionCoordinator
    ) throws -> EraseAllOperationSubjectV1? {
        try requireRecoveryExecution(coordinator: coordinator)
        guard let router else { throw AppAccessContractFailureV1.staleAttempt }
        return try router.originalEraseRecoverySubject(self)
    }

    /// Retained before the no-create source read. This is a read-only
    /// original-ticket owner; it never authorizes a canonical Erase effect.
    func retainOriginalRecoveryPreOpenOwner(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard preparationServiceFrame, preparationCoordinator === coordinator,
              originalRecoveryPreOpenOwner == nil,
              preparationWriterPhase == .absent,
              preparationWriterAllocation == nil,
              preparationFailureWitness == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireRecoveryExecution(coordinator: coordinator)
        originalRecoveryPreOpenOwner = owner
    }

    /// Retains the first auxiliary owner before it opens Support, Caches or
    /// Temporary. A failed capture remains attached to this operation.
    func retainOriginalRecoveryAuxiliaryContinuity(
        _ continuity: StoreOriginalEraseRecoveryAuxiliaryContinuityV1,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard originalRecoveryPreOpenOwner === owner,
              originalRecoveryAuxiliaryContinuity == nil,
              originalRecoveryObservation == owner.observation,
              let intent = originalRecoveryObservation?.intent,
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared,
              originalRecoveryObservation?.preparation?.matches(intent) == true,
              preparationServiceFrame,
              preparationCoordinator === coordinator,
              preparationWriterPhase == .absent,
              preparationWriterAllocation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireRecoveryExecution(coordinator: coordinator)
        originalRecoveryAuxiliaryContinuity = continuity
    }

    /// Identity-only under the pre-open owner's held G. The owner independently
    /// proves G and EX; this predicate never opens a second Registry reader.
    func requireOriginalRecoveryAuxiliaryContinuity(
        _ continuity: StoreOriginalEraseRecoveryAuxiliaryContinuityV1,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard originalRecoveryAuxiliaryContinuity === continuity,
              originalRecoveryPreOpenOwner === owner,
              preparationServiceFrame,
              preparationCoordinator === coordinator,
              let intent = originalRecoveryObservation?.intent,
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared,
              originalRecoveryObservation?.preparation?.matches(intent) == true,
              preparationWriterPhase == .absent,
              preparationWriterAllocation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// The recovery observer's first physical image is captured before its
    /// first await. For this original P cut it must be the exact first image
    /// retained before pointer effects, not a newly accepted survivor.
    func requireOriginalRecoveryAuxiliaryFirstMatchesOriginalP(
        _ observed: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard originalRecoveryPreOpenOwner === owner,
              originalRecoveryAuxiliaryContinuity != nil,
              preparationCoordinator === coordinator,
              originalRecoveryObservation?.intent?.phase
                == .emptyGenerationPrepared,
              let first = originalAuxiliaryFirstSnapshot,
              first == observed,
              !detached, !detaching else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireRecoveryExecution(coordinator: coordinator)
        originalRecoveryAuxiliaryFirstMatchesOriginalP = true
    }

    /// Retain only the one checked-close Q projection derived from that
    /// exact original P image and the checked ScratchData receipt chain.
    func retainOriginalRecoveryPostPointerAuxiliaryProjection(
        _ projection: OriginalRecoveryPostPointerAuxiliaryProjectionV1,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard originalRecoveryAuxiliaryFirstMatchesOriginalP,
              originalRecoveryPreOpenOwner === owner,
              originalRecoveryAuxiliaryContinuity?.isCheckedClosed == true,
              originalRecoveryPostPointerAuxiliaryProjection == nil,
              originalRecoveryPostPointerOwner == nil,
              preparationCoordinator === coordinator,
              let first = originalAuxiliaryFirstSnapshot,
              originalAuxiliaryProjectedIntent?.phase == .pointerSwitched,
              owner.retainedOriginalExclusion === originalExclusion,
              !detached, !detaching else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireRecoveryExecution(coordinator: coordinator)
        try projection.requireOriginalPFirst(first, operation: self,
            owner: owner)
        originalRecoveryPostPointerAuxiliaryProjection = projection
        originalRecoveryPostPointerOwner = owner
        originalTargetReaderStartingImage = .retainedRecovery(projection, owner)
    }

    func releaseOriginalRecoveryAuxiliaryContinuity(
        _ continuity: StoreOriginalEraseRecoveryAuxiliaryContinuityV1,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        try requireOriginalRecoveryAuxiliaryContinuity(
            continuity, owner: owner, coordinator: coordinator)
        guard continuity.isCheckedClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalRecoveryAuxiliaryContinuity = nil
    }

    func requireOriginalRecoveryPreOpenCensus(
        _ leases: [GenerationLeaseTokenV1], registry: GenerationLeaseRegistryV1,
        sourceWriter: GenerationLeaseHandleV1
    ) throws {
        guard originalRecoveryPreOpenOwner != nil,
              preparationServiceFrame,
              preparationWriterPhase == .absent,
              preparationWriterAllocation == nil,
              preparationFailureWitness == nil,
              preparationSourceWriter === sourceWriter else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try inventory.requirePreparationCensus(leases,
            registry: registry, sourceWriter: sourceWriter, writer: nil,
            checkedOriginalRecovery: true)
    }

    func bindOriginalRecoveryObservation(
        _ value: EraseIntentStore.OriginalRecoveryObservation,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) throws {
        guard originalRecoveryPreOpenOwner === owner,
              let router,
              let subject = try router.originalEraseRecoverySubject(self),
              value.supportDevice == subject.applicationSupportDevice,
              value.supportInode == subject.applicationSupportInode,
              originalRecoveryObservation.map({ $0 == value }) ?? true else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let intent = value.intent {
            guard intent.eraseID == subject.eraseID,
                  intent.newGenerationID == subject.newGenerationID,
                  intent.oldGenerationID == owner.source.generationID,
                  EraseIntentCodecV1.valid(intent),
                  ((intent.schemaVersion == 1 && value.preparation == nil)
                      || (intent.schemaVersion == 2
                          && intent.oldPointer?.generationID == owner.source.generationID
                          && intent.oldPointer?.workspaceID == owner.source.workspaceID.rawValue
                          && (value.preparation?.matches(intent) == true
                              || intent.phase == .cleanupComplete))) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            if originalExclusion != nil {
                guard intent.phase == .emptyGenerationPrepared,
                      let admission = originalAuxiliaryRosterAdmission,
                      let store = originalAuxiliaryStore,
                      originalAuxiliaryProjectedIntent == intent else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try value.requireOriginalAuxiliaryRoster(
                    admission.receipt, store: store, operation: self,
                    seal: admission.seal)
            }
        } else {
            guard value.preparation == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        originalRecoveryObservation = value
    }

    func releaseOriginalRecoveryPreOpenOwner(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard originalRecoveryPreOpenOwner === owner,
              owner.observation == originalRecoveryObservation,
              originalRecoveryObservation != nil,
              preparationCoordinator === coordinator else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireRecoveryExecution(coordinator: coordinator)
        originalRecoveryPreOpenOwner = nil
    }

    func requireAbsentOriginalC05Store(
        coordinator: StoreSessionCoordinator,
        applicationSupportURL: URL,
        expectedSupportIdentity: StoreApplicationSupportIdentity
    ) async throws {
        try requireLiveExecution(coordinator: coordinator)
        guard originalC05Runner == nil,
              originalC05AbsentStoreObserver == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let observer = try LocalJobStoreV1(
            applicationSupportURL: applicationSupportURL)
        originalC05AbsentStoreObserver = observer
        let observed = try await observer.beginOriginalEraseNoRepairObservation(
            operationID: ticket.operationID,
            expectedSupportIdentity: expectedSupportIdentity)
        guard observed == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireLiveExecution(coordinator: coordinator)
    }

    func revalidateAbsentOriginalC05Store(
        coordinator: StoreSessionCoordinator
    ) async throws {
        try requireLiveExecution(coordinator: coordinator)
        guard originalC05Runner == nil,
              let observer = originalC05AbsentStoreObserver,
              try await observer.requireOriginalEraseNoRepairBaseline(
                operationID: ticket.operationID) == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireLiveExecution(coordinator: coordinator)
    }

    func releaseOriginalC05ProducerAfterNoEffect(
        coordinator: StoreSessionCoordinator
    ) async throws {
        try requireLiveExecution(coordinator: coordinator)
        if originalC05Runner != nil {
            try await releaseOriginalC05ObservationFenceAfterNoEffect(
                coordinator: coordinator)
        } else if let originalC05AbsentStoreObserver {
            try await originalC05AbsentStoreObserver
                .releaseOriginalEraseNoRepairObservation(
                    operationID: ticket.operationID)
        }
        try coordinator.releaseOriginalC05CaptureAfterNoEffect(
            operationID: ticket.operationID)
        try requireLiveExecution(coordinator: coordinator)
    }

    func beginOriginalC05ObservationFence(
        coordinator: StoreSessionCoordinator,
        expectedSupportIdentity: StoreApplicationSupportIdentity
    ) async throws {
        try requireLiveExecution(coordinator: coordinator)
        guard let originalC05Runner else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await originalC05Runner.beginOriginalEraseObservationFence(
            ticket.operationID,
            expectedSupportIdentity: expectedSupportIdentity)
        try requireLiveExecution(coordinator: coordinator)
    }

    func requireOriginalC05ObservationFence(
        coordinator: StoreSessionCoordinator
    ) async throws -> LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1? {
        try requireLiveExecution(coordinator: coordinator)
        guard let originalC05Runner else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let observed = try await originalC05Runner
            .requireOriginalEraseObservationFence(ticket.operationID)
        try requireLiveExecution(coordinator: coordinator)
        return observed
    }

    /// The pre-marker no-effect branch alone may reopen C05 producer
    /// admission. After a V3 pending marker the original runner stays fenced.
    func releaseOriginalC05ObservationFenceAfterNoEffect(
        coordinator: StoreSessionCoordinator
    ) async throws {
        try requireLiveExecution(coordinator: coordinator)
        guard let originalC05Runner else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await originalC05Runner.releaseOriginalEraseObservationFence(
            ticket.operationID)
        try requireLiveExecution(coordinator: coordinator)
    }

    func drainOriginalC05AfterPendingPreparation(
        coordinator: StoreSessionCoordinator,
        authority: OriginalC05PendingDrainAuthorityV1
    ) async throws {
        try requireLiveExecution(coordinator: coordinator)
        guard let originalC05Runner else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        guard authority.operationID == ticket.operationID else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await originalC05Runner.eraseAllForOriginalOperation(
            ticket.operationID, authority: authority)
        try requireLiveExecution(coordinator: coordinator)
    }

    func requireDurableOriginalC05PendingPreparation(
        coordinator: StoreSessionCoordinator,
        store: EraseIntentStore,
        expected: ErasePreparationV2,
        eraseID: UUID
    ) throws -> OriginalC05PendingDrainAuthorityV1 {
        try requireLiveExecution(coordinator: coordinator)
        guard let drain = expected.c05JobDrainV3,
              drain.phase == .pending,
              drain.eraseID == eraseID,
              try store.loadPreparation() == expected,
              originalC05Runner != nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return OriginalC05PendingDrainAuthorityV1(
            operationID: ticket.operationID)
    }

    func requireOriginalC05StoreEmpty(
        coordinator: StoreSessionCoordinator
    ) async throws -> LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1 {
        try requireLiveExecution(coordinator: coordinator)
        guard let originalC05Runner else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let snapshot = try await originalC05Runner.requireOriginalEraseStoreEmpty(
            ticket.operationID)
        try requireLiveExecution(coordinator: coordinator)
        return snapshot
    }

    func removeOriginalC05DrainedRoot(
        coordinator: StoreSessionCoordinator,
        store: EraseIntentStore,
        expected: ErasePreparationV2
    ) async throws {
        try requireLiveExecution(coordinator: coordinator)
        guard let drain = expected.c05JobDrainV3,
              drain.phase == .drained,
              try store.loadPreparation() == expected,
              let originalC05Runner else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await originalC05Runner.removeOriginalEraseDrainedRoot(
            drain, operationID: ticket.operationID)
        try requireLiveExecution(coordinator: coordinator)
    }

    func retireOriginalC05EffectsAfterRootRemoved(
        coordinator: StoreSessionCoordinator,
        store: EraseIntentStore,
        expected: ErasePreparationV2
    ) async throws {
        try requireLiveExecution(coordinator: coordinator)
        guard let drain = expected.c05JobDrainV3,
              drain.phase == .rootRemoved,
              try store.loadPreparation() == expected,
              let originalC05Runner else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await originalC05Runner.retireOriginalEraseEffects(ticket.operationID)
        try requireLiveExecution(coordinator: coordinator)
    }

    func requireRecoveryExecution(coordinator: StoreSessionCoordinator) throws {
        guard let router, !detached, prepared == nil else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
    }

    func retainOriginalC05NoRepairReader(
        _ reader: EraseC05ColdPreparationJournalReaderV1,
        coordinator: StoreSessionCoordinator,
        applicationSupportURL: URL
    ) throws {
        try requireRecoveryExecution(coordinator: coordinator)
        guard preparationServiceFrame, !originalC05NoRepairReaderOpen,
              !originalC05NoRepairReaderUncertain,
              applicationSupportURL.standardizedFileURL
                == coordinator.checkRunnerPhotoApplicationSupportURL.standardizedFileURL else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        originalC05NoRepairReaders.append(reader)
        originalC05NoRepairReaderOpen = true
    }

    func requireOriginalC05NoRepairReader(
        _ reader: EraseC05ColdPreparationJournalReaderV1,
        coordinator: StoreSessionCoordinator,
        applicationSupportURL: URL?
    ) throws {
        try requireRecoveryExecution(coordinator: coordinator)
        guard preparationServiceFrame, originalC05NoRepairReaderOpen,
              !originalC05NoRepairReaderUncertain,
              originalC05NoRepairReaders.last === reader,
              applicationSupportURL?.standardizedFileURL
                == coordinator.checkRunnerPhotoApplicationSupportURL.standardizedFileURL else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    func closeOriginalC05NoRepairReaderChecked(
        _ reader: EraseC05ColdPreparationJournalReaderV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        try requireOriginalC05NoRepairReader(
            reader, coordinator: coordinator,
            applicationSupportURL: coordinator.checkRunnerPhotoApplicationSupportURL)
        do {
            try reader.closeChecked()
        } catch {
            originalC05NoRepairReaderUncertain = true
            throw error
        }
        originalC05NoRepairReaderOpen = false
    }

    func requirePreparationRollback() throws {
        guard !originalC05NoRepairReaderOpen,
              !originalC05NoRepairReaderUncertain else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requirePreparationRollbackSource()
    }

    func requirePreparationRollbackWithOriginalNoRepairReader(
        _ reader: EraseC05ColdPreparationJournalReaderV1,
        coordinator: StoreSessionCoordinator,
        expected: ErasePreparationV2
    ) throws {
        try requireOriginalC05NoRepairReader(reader,
            coordinator: coordinator,
            applicationSupportURL: coordinator.checkRunnerPhotoApplicationSupportURL)
        guard expected.c05JobDrainV3 == nil,
              try reader.currentOriginalPreparation(
                operation: self, coordinator: coordinator) == expected else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requirePreparationRollbackSource()
    }

    private func requirePreparationRollbackSource() throws {
        guard let router, preparationServiceFrame, !detached, !detaching,
              !originalC05NoRepairReaderUncertain,
              prepared == nil, drain == nil, originalExclusion == nil,
              transferredExclusion == nil, !startedExclusionAcquisition,
              preparationWriterPhase == .absent,
              preparationWriterAllocation == nil,
              preparationTargetSession == nil, preparationTargetWriter == nil,
              preparationFailureWitness == nil,
              let source = preparationSourceWriter,
              let registry = preparationRegistry else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireEraseRetirementOperation(self)
        try source.requireLiveTemporalIdentity(mutationRegistry: registry)
        try inventory.requireSourceOnlyPreparationForAbort(
            sourceEpoch: source.token.epoch, registry: registry)
    }

    // Keep uncertain close ownership on the actual operation; never throw
    // away an opened observer or reuse a previously successful absence result.
    private var unadmittedControlObservations: [EraseUnadmittedControlObservationV1] = []

    fileprivate func requireUnadmittedControlsAbsent(applicationSupportURL: URL,
        coordinator: StoreSessionCoordinator, writer: WorkspaceWriterV1) throws {
        try requireUnadmittedReturn()
        guard unadmittedControlObservations.allSatisfy({
            $0.status == .absentAndClosed || $0.status == .refusedAndClosed
        }) else { throw AppAccessContractFailureV1.staleAttempt }
        let identity = try coordinator.originalWriterSupportIdentityForUnadmittedErase(
            expectedWriter: writer)
        let observation = EraseUnadmittedControlObservationV1(
            applicationSupportURL: applicationSupportURL,
            expectedSourceSupportIdentity: identity)
        unadmittedControlObservations.append(observation) // before opening
        do {
            try observation.requireAbsent()
        } catch {
            if observation.status == .refused { try observation.closeAfterRefusal() }
            throw error
        }
        guard observation.status == .absentAndClosed else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    fileprivate func requireUnadmittedReturn() throws {
        guard !preparationServiceFrame, preparationWriterPhase == .absent,
              preparationWriterAllocation == nil, preparationTargetSession == nil,
              preparationTargetWriter == nil, preparationFailureWitness == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireNoRetirementResourcesForAbort()
    }

    fileprivate func requireNoRetirementResourcesForAbort() throws {
        guard !detached, !detaching, prepared == nil, drain == nil,
              originalExclusion == nil, transferredExclusion == nil,
              !startedExclusionAcquisition else { throw AppAccessContractFailureV1.staleAttempt }
        if let preparationFailureWitness {
            try preparationFailureWitness.requireDisposed()
        } else {
            try inventory.requireNoConstructedResourcesForAbort()
        }
    }

    fileprivate func requireCheckedSourceWriterReleaseForAbortedReaderRetirement(
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard !preparationServiceFrame, !detached,
              let source = preparationSourceWriter,
              source.token.epoch.generationID == receipt.originalGenerationID,
              receipt.reservation.subject == receipt.subject,
              receipt.subject.newGenerationID != receipt.originalGenerationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try source.requireClosedForAbortedEraseReaderRetirement()
    }

    func requirePreparing(coordinator: StoreSessionCoordinator) throws -> EraseRetirementBindingV1 {
        guard let router, !detached, prepared == nil else { throw AppAccessContractFailureV1.staleAttempt }
        let actual = try router.eraseRetirementBinding(self, coordinator: coordinator)
        guard binding == nil || binding == actual else { throw AppAccessContractFailureV1.staleAttempt }
        binding = actual
        return actual
    }

    func retainPrepared(_ value: EraseCleanupAfterRetirementV1) throws {
        guard let router, !detached, prepared == nil, value.binding == binding else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try router.requireEraseRetirementOperation(self)
        prepared = value
    }

    func detach(coordinator: StoreSessionCoordinator) async throws {
        guard let router, !detaching, !detached, let prepared, let binding else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        #if DEBUG
        print("V23_ERASE_DETACH_V1 stage=source-proof.enter")
        #endif
        try router.requireEraseTransferSource(self, coordinator: coordinator)
        #if DEBUG
        print("V23_ERASE_DETACH_V1 stage=source-proof.complete")
        #endif
        detaching = true
        defer { detaching = false }
        #if DEBUG
        print("V23_ERASE_DETACH_V1 stage=inventory-seal.enter")
        #endif
        if drain == nil { drain = try inventory.seal(binding: binding) }
        #if DEBUG
        print("V23_ERASE_DETACH_V1 stage=inventory-seal.complete")
        #endif
        guard let drain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if transferredExclusion == nil {
            if originalExclusion == nil {
                if startedExclusionAcquisition {
                    originalExclusion = try coordinator.retryTemporalNormalizationExclusion()
                } else {
                    startedExclusionAcquisition = true
                    #if DEBUG
                    print("V23_ERASE_DETACH_V1 stage=exclusion-acquire.enter")
                    #endif
                    originalExclusion = try await coordinator.drainTemporalProducersForNormalization()
                    #if DEBUG
                    print("V23_ERASE_DETACH_V1 stage=exclusion-acquire.complete")
                    #endif
                }
            }
            // Retain the returned EX before checking a potentially revoked
            // outer execution. A failure cannot lose the actual acquired owner.
            try router.requireEraseTransferSource(self, coordinator: coordinator)
            guard let originalExclusion else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            #if DEBUG
            print("V23_ERASE_DETACH_V1 stage=permit.enter")
            #endif
            let permit = try router.makeEraseRetirementPermit(ticket, coordinator: coordinator,
                binding: binding, drain: drain, exclusion: originalExclusion)
            #if DEBUG
            print("V23_ERASE_DETACH_V1 stage=permit.complete")
            #endif
            #if DEBUG
            print("V23_ERASE_DETACH_V1 stage=exclusion-transfer.enter")
            #endif
            transferredExclusion = try originalExclusion.transferToEraseRetirement(
                binding: binding, drain: drain, permit: permit)
            #if DEBUG
            print("V23_ERASE_DETACH_V1 stage=exclusion-transfer.complete")
            #endif
        }
        guard let transferredExclusion else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        #if DEBUG
        print("V23_ERASE_DETACH_V1 stage=retirement-retain.enter")
        #endif
        retirement = try prepared.retainTransferredExclusion(transferredExclusion, drain: drain)
        #if DEBUG
        print("V23_ERASE_DETACH_V1 stage=retirement-retain.complete")
        #endif
        // This consuming Router edge drops all of its actual aggregate aliases.
        // Service/caller frames still must return before the weak witness passes.
        #if DEBUG
        print("V23_ERASE_DETACH_V1 stage=aggregate-detach.enter")
        #endif
        try router.detachEraseAggregate(self, coordinator: coordinator)
        #if DEBUG
        print("V23_ERASE_DETACH_V1 stage=aggregate-detach.complete")
        #endif
        originalExclusion = nil
        detached = true
    }

    func advanceCleanup() async throws -> Bool {
#if DEBUG
        guard permitsOriginalEffectForTesting else { throw AppAccessContractFailureV1.staleAttempt }
#endif
        guard let router, detached, let prepared else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireEraseRetirementOperation(self)
        return try await prepared.advance()
    }

    func completedRetirement() throws -> (EraseSessionRetirementV1, ErasedRegistryRetirementProofV1, CompletedEraseReceiptV1?) {
#if DEBUG
        guard permitsOriginalEffectForTesting else { throw AppAccessContractFailureV1.staleAttempt }
#endif
        guard let router, detached, let prepared, let retirement, let proof = prepared.proof,
              retirement.ownsProof(proof) else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireEraseRetirementOperation(self)
        return (retirement, proof, try prepared.completedReceipt())
    }

#if DEBUG
    func ownsPostRetiredPreparedForTesting(
        _ value: EraseCleanupAfterRetirementV1
    ) -> Bool { prepared === value }

    fileprivate func postRetiredProofForColdRestartForTesting()
        throws -> ErasedRegistryRetirementProofV1 {
        guard let prepared, let retirement, let proof = prepared.proof,
              retirement.ownsProof(proof) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return proof
    }

    fileprivate func requireInterruptedPostRetiredFaultForAbandonment(
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken
    ) throws -> (GenerationLeaseRegistryV1, String) {
        guard coldRestartAbandonment == .active, detached, !detaching,
              let prepared, let retirement, let proof = prepared.proof,
              retirement.ownsProof(proof),
              let registry = preparationRegistry else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try prepared.requireInterruptedPostRetiredFaultForAbandonmentForTesting(
            subject: subject, reservation: reservation, registry: registry)
        return (registry, try prepared.postRetiredOperationsDigestForTesting())
    }

    fileprivate func abandonInterruptedPostRetiredFaultForColdRestart(
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken,
        registry: GenerationLeaseRegistryV1
    ) throws {
        guard coldRestartAbandonment == .active,
              let prepared, preparationRegistry === registry else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        coldRestartAbandonment = .pending
        do {
            try prepared.abandonInterruptedPostRetiredFaultForTesting(
                subject: subject, reservation: reservation,
                registry: registry)
            coldRestartAbandonment = .abandoned
        } catch {
            coldRestartAbandonment = .closeUncertain
            throw error
        }
    }

    fileprivate func requirePristinePreparedColdExitForTesting(
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken
    ) throws {
        guard coldRestartAbandonment == .active, detached, !detaching,
              let prepared, preparationRegistry != nil,
              let retirement, prepared.retirement === retirement,
              prepared.proof == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try prepared.requirePristineOriginalPreparedColdExitForTesting(
            subject: subject, expectedReservation: reservation)
    }

    fileprivate func beginPristinePreparedColdExitForTesting() throws {
        guard coldRestartAbandonment == .active, detached,
              prepared != nil, preparationRegistry != nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        coldRestartAbandonment = .pending
    }

    fileprivate func finishPristinePreparedColdExitForTesting(
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken
    ) async throws {
        guard coldRestartAbandonment == .pending,
              let prepared, let registry = preparationRegistry else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        do {
            let (proof, operationsDigest) =
                try await prepared.retirePristineOriginalForColdExitForTesting(
                    subject: subject, expectedReservation: reservation,
                    registry: registry)
            try registry.beginPostRetiredEraseCheckedShutdown(
                proof: proof, originalOperationsDigest: operationsDigest)
            try prepared.abandonPristineOriginalForColdExitForTesting(
                subject: subject, expectedReservation: reservation,
                registry: registry)
            coldRestartAbandonment = .abandoned
        } catch {
            coldRestartAbandonment = .closeUncertain
            throw error
        }
    }

    fileprivate func requireInterruptedLateFaultForAbandonment(
        _ expected: EraseAllFailurePoint,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken) throws {
        guard coldRestartAbandonment == .active, detached, !detaching,
              let prepared, let retirement, let proof = prepared.proof,
              retirement.ownsProof(proof) else { throw AppAccessContractFailureV1.staleAttempt }
        try prepared.requireInterruptedLateFaultForAbandonmentForTesting(expected,
            subject: subject, reservation: reservation)
    }

    fileprivate func abandonInterruptedLateFaultForColdRestart(
        _ expected: EraseAllFailurePoint,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken) throws {
        guard coldRestartAbandonment == .active, let prepared else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        coldRestartAbandonment = .pending
        do {
            try prepared.abandonInterruptedLateFaultForTesting(expected,
                subject: subject, reservation: reservation)
            coldRestartAbandonment = .abandoned
        } catch {
            coldRestartAbandonment = .closeUncertain
            throw error
        }
    }
#endif
}

extension StartupRouter {
    func eraseRetirementOperation(for ticket: OriginalOperationTicket) throws -> EraseRouterOperationV1 {
        guard let value = retainedEraseRetirementOperation, value.ticket.owner === ticket.owner,
              value.ticket.mint === ticket.mint, value.ticket.operationID == ticket.operationID else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireEraseRetirementOperation(value)
        return value
    }

    func configureEraseService(_ service: EraseAllService,
        operation: EraseRouterOperationV1) throws -> EraseAllService {
        try requireEraseRetirementOperation(operation)
        guard !operation.detached else { throw AppAccessContractFailureV1.staleAttempt }
        try operation.configurePreparation(factory: generationFactory)
        return try service.configuredForRetirement(factory: generationFactory, inventory: operation.inventory)
    }

    fileprivate func requireEraseRetirementOperation(_ value: EraseRouterOperationV1) throws {
        let ticket = value.ticket
#if DEBUG
        guard value.permitsOriginalEffectForTesting else { throw AppAccessContractFailureV1.staleAttempt }
#endif
        guard retainedEraseRetirementOperation === value, value.router === self,
              ticket.owner === originalOperationOwner,
              let state = originalOperations[ticket.operationID], state.kind == .erase,
              state.owner === ticket.owner, state.mint === ticket.mint else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

#if DEBUG
    /// The completed-abort inventory is armed after the original effects are
    /// poisoned. Reprove the exact retained operation without reopening the
    /// active-only effect gate used by every other Erase transition.
    fileprivate func requireCompletedAbortInventoryBindingOperation(
        _ value: EraseRouterOperationV1
    ) throws {
        let ticket = value.ticket
        guard value.permitsCompletedAbortInventoryBindingForTesting,
              retainedEraseRetirementOperation === value, value.router === self,
              ticket.owner === originalOperationOwner,
              let state = originalOperations[ticket.operationID], state.kind == .erase,
              state.owner === ticket.owner, state.mint === ticket.mint else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    /// The original preparation and detached EX are genuine, with no fault.
    /// Consume every Router continuation while that EX is still held; the
    /// caller may release retained model aliases before the checked finish.
    func beginPristinePreparedEraseColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        originalService: EraseAllService
    ) throws {
        try requireEraseRetirementOperation(value)
        try value.requirePostRetiredAppAccessFenceForTesting(
            originalService: originalService)
        let ticket = value.ticket
        guard let state = originalOperations[ticket.operationID],
              let subject = state.eraseSubject,
              let reservation = state.acknowledgedReservation,
              reservation.subject == subject,
              detachedEraseRetirement === value.retirement,
              pendingEraseDrainProof == nil, operationOwnedWriter == nil,
              pendingErasedActivation == nil, freshEraseAdoption == nil,
              !hasPendingWriterCleanup,
              case let .eraseCleanupPending(.retiring(held)) = route,
              held === value else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try value.requirePristinePreparedColdExitForTesting(
            subject: subject, reservation: reservation)
        try originalService.requirePristineOriginalPreparedColdExitForTesting(
            operation: value, subject: subject,
            reservation: reservation)
        Self.retainedOriginalEraseShutdownOwnersForTesting.append(value)
        Self.retainedPostRetiredOriginalServicesForTesting.append(originalService)
        try originalService.poisonPristineOriginalPreparedColdExitForTesting(
            operation: value, subject: subject,
            reservation: reservation)
        try value.beginPristinePreparedColdExitForTesting()
        abandonedOriginalEraseForColdRestart = true
        originalOperations[ticket.operationID] = nil
        operationID = nil
        operationKind = nil
        operationAuthorization = nil
        isRunning = false
        stopCommerce()
        route = .maintenance(.eraseInconsistent)
    }

    func finishPristinePreparedEraseColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken
    ) async throws {
        guard abandonedOriginalEraseForColdRestart,
              retainedEraseRetirementOperation === value,
              detachedEraseRetirement === value.retirement,
              case .maintenance(.eraseInconsistent) = route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await value.finishPristinePreparedColdExitForTesting(
            subject: subject, reservation: reservation)
    }

    /// The single additive fault is after actual lease retirement but before
    /// any old-generation deletion. The old operation and every descriptor
    /// owner are permanently pinned before the original EX is checked closed.
    func abandonInterruptedPostRetiredEraseForColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        originalService: EraseAllService
    ) throws {
        try requireEraseRetirementOperation(value)
        // An operation ever attached to AppAccess cannot use this direct
        // Router seam until its exact pending shell has fenced and joined.
        try value.requirePostRetiredAppAccessFenceForTesting(
            originalService: originalService)
        let ticket = value.ticket
        guard let state = originalOperations[ticket.operationID],
              let subject = state.eraseSubject,
              let reservation = state.acknowledgedReservation,
              reservation.subject == subject,
              detachedEraseRetirement === value.retirement,
              pendingEraseDrainProof == nil, operationOwnedWriter == nil,
              pendingErasedActivation == nil, freshEraseAdoption == nil,
              !hasPendingWriterCleanup,
              case let .eraseCleanupPending(.retiring(held)) = route,
              held === value else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let (registry, operationsDigest) = try value
            .requireInterruptedPostRetiredFaultForAbandonment(
                subject: subject, reservation: reservation)
        try originalService.requirePostRetiredOriginalServiceForTesting(
            operation: value)
        Self.retainedOriginalEraseShutdownOwnersForTesting.append(value)
        Self.retainedPostRetiredOriginalServicesForTesting.append(originalService)
        try originalService.poisonPostRetiredOriginalServiceForTesting(
            operation: value)
        // The original ticket and callback continuations are terminal before
        // installing the selective fence or releasing the actual EX.
        abandonedOriginalEraseForColdRestart = true
        originalOperations[ticket.operationID] = nil
        operationID = nil
        operationKind = nil
        operationAuthorization = nil
        isRunning = false
        stopCommerce()
        route = .maintenance(.eraseInconsistent)
        try registry.beginPostRetiredEraseCheckedShutdown(
            proof: try value.postRetiredProofForColdRestartForTesting(),
            originalOperationsDigest: operationsDigest)
        try value.abandonInterruptedPostRetiredFaultForColdRestart(
            subject: subject, reservation: reservation, registry: registry)
    }

    /// Controlled test-host restart boundary for the four faults after real
    /// namespace retirement. It never creates a receipt or changes Erase
    /// intent/pointer/tree bytes. The retained old owner remains inspectable.
    func abandonInterruptedLateEraseForColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        expectedFault: EraseAllFailurePoint) throws {
        try requireEraseRetirementOperation(value)
        let ticket = value.ticket
        guard let state = originalOperations[ticket.operationID],
              let subject = state.eraseSubject,
              let reservation = state.acknowledgedReservation,
              reservation.subject == subject,
              detachedEraseRetirement === value.retirement,
              pendingEraseDrainProof == nil, operationOwnedWriter == nil,
              pendingErasedActivation == nil, freshEraseAdoption == nil,
              !hasPendingWriterCleanup else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        guard case let .eraseCleanupPending(.retiring(held)) = route,
              held === value else { throw AppAccessContractFailureV1.staleAttempt }
        try value.requireInterruptedLateFaultForAbandonment(expectedFault,
            subject: subject, reservation: reservation)
        // Consume all Router continuations before the first physical unlock.
        abandonedOriginalEraseForColdRestart = true
        originalOperations[ticket.operationID] = nil
        operationID = nil
        operationKind = nil
        operationAuthorization = nil
        isRunning = false
        stopCommerce()
        route = .maintenance(.eraseInconsistent)
        try value.abandonInterruptedLateFaultForColdRestart(expectedFault,
            subject: subject, reservation: reservation)
    }
#endif

#if DEBUG
    /// Before an Erase target is activated, beginEraseOperation leaves the
    /// original source under `.checking`. The private ticket/subject checks at
    /// each caller bind this predicate to one authentic original Erase; this
    /// helper only compares the retained source-owner route and writer graph.
    private func completedAbortSourceRouteMatchesForTesting(
        _ coordinator: StoreSessionCoordinator,
        liveTicket: OriginalOperationTicket?
    ) -> Bool {
        switch route {
        case .checking:
            let phaseBound = liveTicket.map({
                operationID == $0.operationID && operationKind == .erase && isRunning
            }) ?? abandonedOriginalEraseForColdRestart
            return phaseBound && pendingEraseDrainProof != nil
                && operationOwnedWriter.map({
                    $0.coordinator === coordinator
                        && $0.writer === coordinator.workspaceWriter
                }) == true
                && pendingErasedActivation == nil
                && detachedEraseRetirement == nil
        case .eraseCleanupPending(.preparing(let actual)):
            return actual === coordinator
        default:
            return false
        }
    }

    /// The authentic no-effect receipt is already returned by the original
    /// Service frame. Consume Router effects and close temporal admission
    /// synchronously before AppAccess awaits lifecycle abandonment.
    func poisonCompletedAbortColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        service: EraseAllService,
        receipt: AbortedEraseAdmissionReceiptV1,
        expectedFault: EraseAllFailurePoint
    ) throws {
        do {
            try requireEraseRetirementOperation(value)
        } catch {
            FileHandle.standardError.write(Data(
                "ERASE_COMPLETED_ABORT_POISON_PREFLIGHT_V1 stage=operation\n".utf8))
            throw error
        }
        do {
            try service.requireCompletedAbortColdShutdownForTesting(
                expectedFault, operation: value, receipt: receipt)
        } catch {
            FileHandle.standardError.write(Data(
                "ERASE_COMPLETED_ABORT_POISON_PREFLIGHT_V1 stage=service\n".utf8))
            throw error
        }
        let ticket = value.ticket
        guard completedAbortShutdown == nil, completedAbortFinal == nil,
              let state = originalOperations[ticket.operationID],
              state.kind == .erase,
              state.eraseSubject == receipt.subject,
              state.acknowledgedReservation == receipt.reservation,
              state.sourceGenerationID == receipt.originalGenerationID,
              state.eraseAuthorizationIssued,
              receipt.reservation.subject == receipt.subject,
              !value.detached, detachedEraseRetirement == nil,
              retainedEraseRetirementOperation === value,
              !hasPendingWriterCleanup,
              let coordinator = state.source.coordinator,
              completedAbortSourceRouteMatchesForTesting(
                  coordinator, liveTicket: ticket) else {
            // Diagnostic only: classify the already-refused in-memory guard.
            // The original short-circuit expression above remains authority.
            let category: String
            if completedAbortShutdown != nil || completedAbortFinal != nil {
                category = "shutdown-state"
            } else if let observed = originalOperations[ticket.operationID] {
                if observed.kind != .erase { category = "operation-kind" }
                else if observed.eraseSubject != receipt.subject { category = "subject" }
                else if observed.acknowledgedReservation != receipt.reservation {
                    category = "reservation"
                } else if observed.sourceGenerationID != receipt.originalGenerationID {
                    category = "source-generation"
                } else if !observed.eraseAuthorizationIssued {
                    category = "authorization-issued"
                } else if receipt.reservation.subject != receipt.subject {
                    category = "receipt-subject"
                } else if value.detached || detachedEraseRetirement != nil {
                    category = "detached"
                } else if retainedEraseRetirementOperation !== value {
                    category = "retained-operation"
                } else if hasPendingWriterCleanup {
                    category = "pending-writer-cleanup"
                } else if let coordinator = observed.source.coordinator {
                    category = completedAbortSourceRouteMatchesForTesting(
                        coordinator, liveTicket: ticket) ? "unclassified" : "source-route"
                } else {
                    category = "source-coordinator"
                }
            } else {
                category = "operation-state"
            }
            FileHandle.standardError.write(Data((
                "ERASE_COMPLETED_ABORT_POISON_PREFLIGHT_V1 stage=" + category + "\n"
            ).utf8))
            throw AppAccessContractFailureV1.staleAttempt
        }
        do {
            try value.requireNoRetirementResourcesForAbort()
        } catch {
            FileHandle.standardError.write(Data(
                "ERASE_COMPLETED_ABORT_POISON_PREFLIGHT_V1 stage=resource-proof\n".utf8))
            throw error
        }
        do {
            try value.poisonInterruptedOriginalPreparation(
                sourceGenerationID: state.sourceGenerationID,
                targetGenerationID: receipt.subject.newGenerationID,
                completedAbort: true)
        } catch {
            FileHandle.standardError.write(Data(
                "ERASE_COMPLETED_ABORT_POISON_PREFLIGHT_V1 stage=operation-poison\n".utf8))
            throw error
        }
        Self.retainedOriginalEraseShutdownOwnersForTesting.append(value)
        completedAbortShutdown = CompletedAbortShutdown(
            operation: value, service: service, receipt: receipt,
            coordinator: coordinator)
        abandonedOriginalEraseForColdRestart = true
        originalOperations[ticket.operationID] = nil
        operationID = nil
        operationKind = nil
        operationAuthorization = nil
        isRunning = false
        stopCommerce()
        let drainID: UUID
        do {
            drainID = try coordinator.closeProducerAdmissionForOriginalEraseShutdown()
        } catch {
            FileHandle.standardError.write(Data(
                "ERASE_COMPLETED_ABORT_POISON_PREFLIGHT_V1 stage=producer-close\n".utf8))
            throw error
        }
        completedAbortShutdown?.drainID = drainID
        coordinator.workspaceWriter.invalidate()
    }

    func markCompletedAbortLifecycleReleasedForTesting(
        _ value: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard abandonedOriginalEraseForColdRestart,
              completedAbortShutdown?.operation === value,
              completedAbortShutdown?.receipt.matchesExactOriginalAuthority(receipt) == true,
              completedAbortShutdown?.drainID != nil,
              completedAbortShutdown?.lifecycleReleased == false else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        completedAbortShutdown?.lifecycleReleased = true
    }

    func continueCompletedAbortColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) async throws {
        var diagnosticStage = "initial-authority"
        do {
        guard abandonedOriginalEraseForColdRestart,
              let held = completedAbortShutdown,
              held.operation === value,
              held.receipt.matchesExactOriginalAuthority(receipt),
              held.lifecycleReleased,
              let drainID = held.drainID,
              completedAbortSourceRouteMatchesForTesting(
                  held.coordinator, liveTicket: nil) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let coordinator = held.coordinator
        diagnosticStage = "producer-await"
        try await coordinator.awaitProducersForOriginalEraseShutdown(drainID)
        guard completedAbortShutdown?.operation === value,
              completedAbortShutdown?.drainID == drainID,
              completedAbortShutdown?.lifecycleReleased == true,
              completedAbortSourceRouteMatchesForTesting(
                  coordinator, liveTicket: nil) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        diagnosticStage = "producer-drain-before-proof"
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        diagnosticStage = "service-no-effect"
        try held.service.requireCompletedAbortNoEffectForTesting(
            operation: value, receipt: receipt)
        diagnosticStage = "capture-control"
        let control = try coordinator.captureOriginalEraseShutdownControl(operation: value)
        guard !control.installed else { throw AppAccessContractFailureV1.staleAttempt }
        diagnosticStage = "seal-witness"
        let witness = try value.prepareOriginalShutdownControls(
            registry: control.registry, writer: control.writer, installed: false)
        diagnosticStage = "begin-registry-shutdown"
        try control.registry.beginOriginalEraseCheckedShutdown(witness)
        diagnosticStage = "producer-drain-after-fence"
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        diagnosticStage = "normalization-activity"
        try control.registry.acquireTemporalNormalizationActivityForOriginalEraseShutdown(
            witness: witness, retainedWriter: control.writer.token,
            retain: { try value.retainOriginalShutdownActivity($0, registry: control.registry) })
        diagnosticStage = "physical-root-create"
        let root = try StoreTemporalPhysicalRootExclusionV1
            .unacquiredOriginalEraseShutdown(at: control.supportURL)
        diagnosticStage = "physical-root-retain"
        try value.retainOriginalShutdownRoot(root)
        diagnosticStage = "physical-root-acquire"
        try root.acquireOriginalEraseShutdown()
        diagnosticStage = "producer-drain-after-root"
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        diagnosticStage = "fresh-ledger-no-effect"
        try control.registry.requireCompletedAbortNoEffectUnderOriginalShutdown(
            witness: witness, service: held.service,
            operation: value, receipt: receipt, coordinator: coordinator)
        diagnosticStage = "transfer-controls"
        try value.markOriginalShutdownControlsTransferred()
        completedAbortFinal = (value, held.service, receipt)
        completedAbortPreAliasSealed = false
        completedAbortShutdown = nil
        operationOwnedWriter = nil
        pendingErasedActivation = nil
        deferredEraseCoordinator = nil
        maintenanceEraseSession = nil
        maintenanceRestoreSession = nil
        publishedWriter = nil
        preparedStartup = nil
        route = .maintenance(.eraseInconsistent)
        } catch {
            FileHandle.standardError.write(Data((
                "ERASE_COMPLETED_ABORT_ROUTER_V1 stage=" + diagnosticStage + "\n"
            ).utf8))
            throw error
        }
    }

    /// One-use exact-source seal before AppAccess drops its pending aliases.
    /// The final checked-close proof remains unchanged and still runs later.
    func sealCompletedAbortSourceBeforeAliasReleaseForTesting(
        _ value: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        guard abandonedOriginalEraseForColdRestart,
              let final = completedAbortFinal,
              final.operation === value,
              final.receipt.matchesExactOriginalAuthority(receipt),
              !completedAbortPreAliasSealed,
              case .maintenance(.eraseInconsistent) = route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try value.requireCompletedAbortPreAliasNoEffect(
            service: final.service, receipt: receipt,
            coordinator: coordinator)
        completedAbortPreAliasSealed = true
    }

    fileprivate func requireCompletedAbortPreAliasSealForExclusiveScratch(
        _ value: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard abandonedOriginalEraseForColdRestart,
              let final = completedAbortFinal,
              final.operation === value,
              final.receipt.matchesExactOriginalAuthority(receipt),
              completedAbortPreAliasSealed,
              case .maintenance(.eraseInconsistent) = route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    func finishCompletedAbortColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        var diagnosticStage = "final-authority"
        do {
        guard abandonedOriginalEraseForColdRestart,
              let final = completedAbortFinal,
              final.operation === value,
              final.receipt.matchesExactOriginalAuthority(receipt),
              completedAbortPreAliasSealed,
              case .maintenance(.eraseInconsistent) = route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        diagnosticStage = "final-checked-close"
        try value.finishCompletedAbortForColdRestart(
            service: final.service, receipt: receipt)
        completedAbortFinal = nil
        completedAbortPreAliasSealed = false
        } catch {
            FileHandle.standardError.write(Data((
                "ERASE_COMPLETED_ABORT_ROUTER_V1 stage=" + diagnosticStage + "\n"
            ).utf8))
            throw error
        }
    }

    /// Begin a test-host process boundary for an injected original Erase
    /// preparation fault. This consumes the original ticket before any await,
    /// but retains every physical control on the operation until checked exit.
    func beginInterruptedEarlyEraseColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        originalService: EraseAllService,
        expectedFault: EraseAllFailurePoint
    ) async throws {
        try await beginOriginalPreparingEraseColdRestartForTesting(
            value, originalService: originalService,
            expectedFault: expectedFault)
    }

    func beginNotificationRefusalEraseColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        originalService: EraseAllService
    ) async throws {
        try await beginOriginalPreparingEraseColdRestartForTesting(
            value, originalService: originalService,
            expectedFault: nil)
    }

    private func requireInterruptedDurableEraseRouteForTesting(
        operationID: UUID, coordinator: StoreSessionCoordinator,
        targetGenerationID: UUID, expectedFault: EraseAllFailurePoint?,
        durableRetiredFault: Bool
    ) throws {
        if durableRetiredFault && (expectedFault == .afterSessionActivation
            || expectedFault == .beforeSessionPhaseWrite
            || expectedFault == .afterSessionPhaseWrite
            || expectedFault == .beforeCleanup) {
            guard case .checking = route,
                  let activation = pendingErasedActivation,
                  activation.operationID == operationID,
                  activation.owner.coordinator === coordinator,
                  activation.owner.writer === coordinator.workspaceWriter,
                  activation.owner.generationID == targetGenerationID,
                  activation.session.generationID == targetGenerationID,
                  activation.session.modelContext === coordinator.modelContext,
                  activation.session.generationRootURL.standardizedFileURL
                    == coordinator.generationRootURL.standardizedFileURL,
                  let owned = operationOwnedWriter,
                  owned.coordinator === activation.owner.coordinator,
                  owned.writer === activation.owner.writer,
                  owned.generationID == activation.owner.generationID else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            if let retirement = eraseCleanupRetirement {
                guard retirement.operationID == operationID,
                      !retirement.released,
                      retirement.owner.coordinator === activation.owner.coordinator,
                      retirement.owner.writer === activation.owner.writer,
                      retirement.owner.generationID == activation.owner.generationID,
                      retirement.session === activation.session else {
                    throw AppAccessContractFailureV1.staleAttempt
                }
            }
        } else if !durableRetiredFault {
            // Preserve all existing early/notification routes unchanged.
            guard case let .eraseCleanupPending(.preparing(actual)) = route,
                  actual === coordinator else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        } else {
            guard case let .eraseCleanupPending(.preparing(actual)) = route,
                  actual === coordinator,
                  pendingErasedActivation == nil,
                  eraseCleanupRetirement == nil else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        }
    }

    /// A durable pre-activation fault retains the original source writer.
    /// AppAccess may suspend the exact original operation in a preparing
    /// cleanup route after the injected Service error. Neither that route nor
    /// `.checking` authorizes a replacement writer or target activation.
    /// Check both sides of the one-way poison against the same operation.
    private func requirePreactivationDurableEraseRouteForTesting(
        _ value: EraseRouterOperationV1,
        state: OriginalOperationState,
        coordinator: StoreSessionCoordinator,
        subject: EraseAllOperationSubjectV1,
        expectedFault: EraseAllFailurePoint,
        originalService: EraseAllService,
        canonicalIntent: EraseIntentV1,
        poisoned: Bool
    ) throws {
        let expectedPhase: EraseIntentPhaseV1
        switch expectedFault {
        case .afterPreparedWrite, .beforePointerSwitch,
             .afterPointerSwitch, .beforePointerPhaseWrite:
            expectedPhase = .emptyGenerationPrepared
        case .afterPointerPhaseWrite, .beforeSessionActivation:
            expectedPhase = .pointerSwitched
        default:
            throw AppAccessContractFailureV1.staleAttempt
        }
        let ticket = value.ticket
        let routeIsBoundOriginal: Bool
        let routeIsSuspendedOriginal: Bool
        switch route {
        case .checking:
            routeIsBoundOriginal = true
            routeIsSuspendedOriginal = false
        case let .eraseCleanupPending(.preparing(actual)):
            routeIsBoundOriginal = actual === coordinator
            routeIsSuspendedOriginal = routeIsBoundOriginal
        default:
            routeIsBoundOriginal = false
            routeIsSuspendedOriginal = false
        }
        guard canonicalIntent.phase == expectedPhase,
              canonicalIntent.eraseID == subject.eraseID,
              canonicalIntent.newGenerationID == subject.newGenerationID,
              canonicalIntent.oldGenerationID == state.sourceGenerationID,
              state.kind == .erase,
              state.owner === ticket.owner, state.mint === ticket.mint,
              state.source.coordinator === coordinator,
              state.source.modelContext === coordinator.modelContext,
              state.sourceGenerationID == coordinator.generationID,
              routeIsBoundOriginal,
              let owned = operationOwnedWriter,
              owned.coordinator === coordinator,
              owned.writer === coordinator.workspaceWriter,
              owned.generationID == state.sourceGenerationID,
              pendingErasedActivation == nil,
              eraseCleanupRetirement == nil,
              detachedEraseRetirement == nil,
              publishedWriter == nil,
              retainedEraseRetirementOperation === value,
              !hasPendingWriterCleanup else {
#if DEBUG
            let firstFailure: String
            if canonicalIntent.phase != expectedPhase { firstFailure = "intent-phase" }
            else if canonicalIntent.eraseID != subject.eraseID { firstFailure = "intent-erase" }
            else if canonicalIntent.newGenerationID != subject.newGenerationID { firstFailure = "intent-new" }
            else if canonicalIntent.oldGenerationID != state.sourceGenerationID { firstFailure = "intent-old" }
            else if state.kind != .erase { firstFailure = "state-kind" }
            else if !(state.owner === ticket.owner) { firstFailure = "ticket-owner" }
            else if !(state.mint === ticket.mint) { firstFailure = "ticket-mint" }
            else if !(state.source.coordinator === coordinator) { firstFailure = "source-coordinator" }
            else if !(state.source.modelContext === coordinator.modelContext) { firstFailure = "source-context" }
            else if state.sourceGenerationID != coordinator.generationID { firstFailure = "source-generation" }
            else if !routeIsBoundOriginal { firstFailure = "route" }
            else if operationOwnedWriter == nil { firstFailure = "owned-writer-missing" }
            else if let owned = operationOwnedWriter,
                    !(owned.coordinator === coordinator) { firstFailure = "owned-coordinator" }
            else if let owned = operationOwnedWriter,
                    !(owned.writer === coordinator.workspaceWriter) { firstFailure = "owned-writer" }
            else if let owned = operationOwnedWriter,
                    owned.generationID != state.sourceGenerationID { firstFailure = "owned-generation" }
            else if pendingErasedActivation != nil { firstFailure = "pending-activation" }
            else if eraseCleanupRetirement != nil { firstFailure = "cleanup-retirement" }
            else if detachedEraseRetirement != nil { firstFailure = "detached-retirement" }
            else if publishedWriter != nil { firstFailure = "published-writer" }
            else if !(retainedEraseRetirementOperation === value) { firstFailure = "retained-operation" }
            else if hasPendingWriterCleanup { firstFailure = "writer-cleanup" }
            else { firstFailure = "changed-during-check" }
            FileHandle.standardError.write(Data((
                "V906_PREACTIVATION_ROUTE_GUARD_V1 first=" + firstFailure + "\n"
            ).utf8))
#endif
            throw AppAccessContractFailureV1.staleAttempt
        }
        if poisoned {
            guard abandonedOriginalEraseForColdRestart,
                  originalOperations[ticket.operationID] == nil,
                  operationID == nil, operationKind == nil,
                  !isRunning else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            guard try originalService.interruptedRetiredAuthorityIntentForTesting(
                expectedFault, operation: value) == canonicalIntent else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        } else {
            let originalKind: Bool
            switch operationKind {
            case .erase: originalKind = true
            default: originalKind = false
            }
            // AppAccess suspends the admitted original after the injected
            // Service error: it clears execution flags and revokes command
            // admission while retaining the exact ticket and lease wrapper.
            // The ordinary `.checking` route still requires live execution.
            let executionMatches = routeIsSuspendedOriginal
                ? operationID == nil && operationKind == nil && !isRunning
                    && operationAuthorization == nil
                : operationID == ticket.operationID && originalKind && isRunning
            guard !abandonedOriginalEraseForColdRestart,
                  executionMatches,
                  originalOperations[ticket.operationID]?.owner === state.owner,
                  originalOperations[ticket.operationID]?.mint === state.mint else {
#if DEBUG
                let firstFailure: String
                if abandonedOriginalEraseForColdRestart { firstFailure = "abandoned" }
                else if routeIsSuspendedOriginal && !executionMatches {
                    firstFailure = "suspended-execution"
                } else if operationID != ticket.operationID { firstFailure = "operation-id" }
                else if !originalKind { firstFailure = "operation-kind" }
                else if !isRunning { firstFailure = "not-running" }
                else if !(originalOperations[ticket.operationID]?.owner === state.owner) {
                    firstFailure = "original-owner"
                } else if !(originalOperations[ticket.operationID]?.mint === state.mint) {
                    firstFailure = "original-mint"
                } else { firstFailure = "changed-during-check" }
                FileHandle.standardError.write(Data((
                    "V906_PREACTIVATION_PREPOISON_GUARD_V1 first=" + firstFailure + "\n"
                ).utf8))
#endif
                throw AppAccessContractFailureV1.staleAttempt
            }
        }
        try value.requirePreactivationDurableShutdownAssociation(
            coordinator: coordinator,
            sourceGenerationID: state.sourceGenerationID,
            targetGenerationID: subject.newGenerationID,
            poisoned: poisoned)
    }

    private func beginOriginalPreparingEraseColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        originalService: EraseAllService,
        expectedFault: EraseAllFailurePoint?
    ) async throws {
        try requireEraseRetirementOperation(value)
        let durableRetiredFault: Bool
        let preactivationDurableFault: Bool
        switch expectedFault {
        case .afterPreparedWrite?, .beforePointerSwitch?,
             .afterPointerSwitch?, .beforePointerPhaseWrite?,
             .afterPointerPhaseWrite?, .beforeSessionActivation?:
            durableRetiredFault = true
            preactivationDurableFault = true
        case .afterSessionActivation?, .beforeSessionPhaseWrite?,
             .afterSessionPhaseWrite?, .beforeCleanup?:
            durableRetiredFault = true
            preactivationDurableFault = false
        default:
            durableRetiredFault = false
            preactivationDurableFault = false
        }
        let preactivationIntent: EraseIntentV1?
        if let expectedFault {
            if durableRetiredFault {
                let intent = try originalService.interruptedRetiredAuthorityIntentForTesting(
                    expectedFault, operation: value)
                preactivationIntent = preactivationDurableFault ? intent : nil
            } else {
                try originalService.requireInterruptedOriginalPreparationFaultForTesting(
                    expectedFault, operation: value)
                preactivationIntent = nil
            }
        } else { preactivationIntent = nil }
        // Fixed DEBUG labels only. A missing `.complete` locates the exact
        // original-owner shutdown boundary without logging owner identities.
        func tracePreactivationShutdown(_ stage: String) {
            guard preactivationIntent != nil else { return }
            FileHandle.standardError.write(Data((
                "V23_ERASE_PREACTIVATION_SHUTDOWN_V1 stage=\(stage)\n"
            ).utf8))
        }
        let ticket = value.ticket
        guard let state = originalOperations[ticket.operationID],
              let coordinator = state.source.coordinator,
              let subject = state.eraseSubject,
              let reservation = state.acknowledgedReservation,
              reservation.subject == subject,
              state.eraseAuthorizationIssued,
              !value.detached, detachedEraseRetirement == nil,
              retainedEraseRetirementOperation === value,
              !hasPendingWriterCleanup else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        if let preactivationIntent, let expectedFault {
            tracePreactivationShutdown("route-before-poison.enter")
            try requirePreactivationDurableEraseRouteForTesting(
                value, state: state, coordinator: coordinator,
                subject: subject, expectedFault: expectedFault,
                originalService: originalService,
                canonicalIntent: preactivationIntent, poisoned: false)
            tracePreactivationShutdown("route-before-poison.complete")
            // Retain both the original Router and the exact configured
            // Service before a poisoned path can throw or suspend.
            Self.retainedPreactivationDurableShutdownsForTesting.append(
                (self, originalService))
        } else {
            try requireInterruptedDurableEraseRouteForTesting(
                operationID: ticket.operationID, coordinator: coordinator,
                targetGenerationID: subject.newGenerationID,
                expectedFault: expectedFault,
                durableRetiredFault: durableRetiredFault)
        }
        if expectedFault == nil {
            guard notificationRefusalColdExitForTesting == nil else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            try originalService
                .requireOriginalNotificationReadbackRefusalForColdExitForTesting(
                    operation: value, subject: subject)
        }
        let retainedShutdownExclusion = try value
            .retainedOriginalExclusionForDurableShutdown()
        if durableRetiredFault, let expectedFault {
            tracePreactivationShutdown("poison.enter")
            try value.poisonInterruptedDurableOriginalPreparation(
                sourceGenerationID: state.sourceGenerationID,
                targetGenerationID: subject.newGenerationID,
                expectedFault: expectedFault,
                retainedExclusion: retainedShutdownExclusion)
            tracePreactivationShutdown("poison.complete")
        } else if expectedFault == nil,
                  let retainedShutdownExclusion {
            try value.poisonInterruptedNotificationRefusalWithRetainedExclusion(
                sourceGenerationID: state.sourceGenerationID,
                targetGenerationID: subject.newGenerationID,
                coordinator: coordinator,
                exclusion: retainedShutdownExclusion)
        } else {
            try value.poisonInterruptedOriginalPreparation(
                sourceGenerationID: state.sourceGenerationID,
                targetGenerationID: subject.newGenerationID)
        }
        Self.retainedOriginalEraseShutdownOwnersForTesting.append(value)
        if expectedFault == nil {
            Self.retainedPostRetiredOriginalServicesForTesting.append(
                originalService)
            try originalService
                .poisonOriginalNotificationReadbackRefusalForColdExitForTesting(
                    operation: value, subject: subject)
            notificationRefusalColdExitForTesting =
                (value, originalService, subject)
        }
        // No suspended callback can use the original ticket after this point.
        abandonedOriginalEraseForColdRestart = true
        originalOperations[ticket.operationID] = nil
        operationID = nil
        operationKind = nil
        operationAuthorization = nil
        isRunning = false
        stopCommerce()
        let drainID: UUID?
        if retainedShutdownExclusion == nil {
            tracePreactivationShutdown("producer-close.enter")
            let ownedDrain = try coordinator.closeProducerAdmissionForOriginalEraseShutdown()
            drainID = ownedDrain
            tracePreactivationShutdown("producer-close.complete")
            coordinator.workspaceWriter.invalidate()
            tracePreactivationShutdown("producer-drain.enter")
            try await coordinator.awaitProducersForOriginalEraseShutdown(
                ownedDrain)
            tracePreactivationShutdown("producer-drain.complete")
        } else {
            // The exact Coordinator already closed producer admission and
            // completed its drain before obtaining this retained EX.
            drainID = nil
            coordinator.workspaceWriter.invalidate()
        }
        guard abandonedOriginalEraseForColdRestart,
              retainedEraseRetirementOperation === value else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        if let preactivationIntent, let expectedFault {
            tracePreactivationShutdown("route-after-drain.enter")
            try requirePreactivationDurableEraseRouteForTesting(
                value, state: state, coordinator: coordinator,
                subject: subject, expectedFault: expectedFault,
                originalService: originalService,
                canonicalIntent: preactivationIntent, poisoned: true)
            tracePreactivationShutdown("route-after-drain.complete")
        } else {
            try requireInterruptedDurableEraseRouteForTesting(
                operationID: ticket.operationID, coordinator: coordinator,
                targetGenerationID: subject.newGenerationID,
                expectedFault: expectedFault,
                durableRetiredFault: durableRetiredFault)
        }
        if let drainID {
            try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        }
        tracePreactivationShutdown("control-capture.enter")
        let retainedControl: StoreOriginalEraseRetainedExclusionShutdownControlV1?
        let control: (registry: GenerationLeaseRegistryV1,
            writer: GenerationLeaseHandleV1, supportURL: URL,
            installed: Bool)
        if let retainedShutdownExclusion {
            let captured = try coordinator
                .captureRetainedOriginalEraseShutdownControl(
                    operation: value, exclusion: retainedShutdownExclusion)
            retainedControl = captured
            control = (captured.registry, captured.writer,
                captured.supportURL, captured.installed)
        } else {
            retainedControl = nil
            control = try coordinator.captureOriginalEraseShutdownControl(
                operation: value)
        }
        tracePreactivationShutdown("control-capture.complete")
        tracePreactivationShutdown("inventory-seal.enter")
        let witness = try value.prepareOriginalShutdownControls(
            registry: control.registry, writer: control.writer,
            installed: control.installed)
        tracePreactivationShutdown("inventory-seal.complete")
        // Selective fence and EX proof are synchronous with no await.
        tracePreactivationShutdown("registry-g.enter")
        try control.registry.beginOriginalEraseCheckedShutdown(witness)
        tracePreactivationShutdown("registry-g.complete")
        let retainedRegistryReceipt: OriginalEraseRetainedExclusionShutdownRegistryReceiptV1?
        if let retainedControl {
            tracePreactivationShutdown("registry-ex.reuse.enter")
            try value.retainOriginalShutdownExistingExclusion(
                retainedControl)
            retainedRegistryReceipt = try control.registry
                .retainExistingTemporalNormalizationActivityForOriginalEraseShutdown(
                    witness: witness, activity: retainedControl.activity,
                    retainedWriter: control.writer.token)
            tracePreactivationShutdown("registry-ex.reuse.complete")
        } else {
            retainedRegistryReceipt = nil
            guard let drainID else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
            tracePreactivationShutdown("registry-ex.enter")
            try control.registry.acquireTemporalNormalizationActivityForOriginalEraseShutdown(
                witness: witness, retainedWriter: control.writer.token,
                retain: { try value.retainOriginalShutdownActivity($0, registry: control.registry) })
            tracePreactivationShutdown("registry-ex.complete")
            tracePreactivationShutdown("root-owner.enter")
            let root = try StoreTemporalPhysicalRootExclusionV1
                .unacquiredOriginalEraseShutdown(at: control.supportURL)
            try value.retainOriginalShutdownRoot(root)
            tracePreactivationShutdown("root-owner.complete")
            tracePreactivationShutdown("root-ex.enter")
            try root.acquireOriginalEraseShutdown()
            tracePreactivationShutdown("root-ex.complete")
            try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        }
        if expectedFault == .afterPointerSwitch,
           preactivationIntent != nil {
            tracePreactivationShutdown("v949-sqlite-preclose.enter")
            try value.beginV949OwnedSourceCloseTransition()
            tracePreactivationShutdown("v949-sqlite-preclose.complete")
        }
        coordinator.workspaceWriter.invalidate()
        // If another genuine activation route retained the target strongly,
        // reprove its exact identity before transferring that aggregate.
        if let preactivationIntent, let expectedFault {
            tracePreactivationShutdown("route-before-transfer.enter")
            try requirePreactivationDurableEraseRouteForTesting(
                value, state: state, coordinator: coordinator,
                subject: subject, expectedFault: expectedFault,
                originalService: originalService,
                canonicalIntent: preactivationIntent, poisoned: true)
            guard !control.installed else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            tracePreactivationShutdown("route-before-transfer.complete")
        } else {
            try requireInterruptedDurableEraseRouteForTesting(
                operationID: ticket.operationID, coordinator: coordinator,
                targetGenerationID: subject.newGenerationID,
                expectedFault: expectedFault,
                durableRetiredFault: durableRetiredFault)
        }
        tracePreactivationShutdown("transfer.enter")
        try value.markOriginalShutdownControlsTransferred()
        if let retainedControl {
            guard let retainedRegistryReceipt else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try value.detachOriginalShutdownRetainedExclusion(
                retainedControl, registryReceipt: retainedRegistryReceipt)
        }
        tracePreactivationShutdown("transfer.complete")
        // The operation now owns only exact handles, weak observations, EX,
        // physical root and the inert registry. The matched retirement owner
        // must be released before the weak target-session drain.
        if expectedFault == .afterSessionPhaseWrite {
            eraseCleanupRetirement = nil
        }
        operationOwnedWriter = nil
        pendingErasedActivation = nil
        deferredEraseCoordinator = nil
        maintenanceEraseSession = nil
        maintenanceRestoreSession = nil
        publishedWriter = nil
        preparedStartup = nil
        route = .maintenance(.eraseInconsistent)
    }

    /// Called only after the caller has dropped its source/target aliases.
    /// A still-live weak observation throws without changing durable Erase.
    func finishInterruptedEarlyEraseColdRestartForTesting(
        _ value: EraseRouterOperationV1
    ) throws {
        guard abandonedOriginalEraseForColdRestart,
              notificationRefusalColdExitForTesting == nil,
              retainedEraseRetirementOperation === value,
              case .maintenance(.eraseInconsistent) = route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try value.finishInterruptedOriginalPreparationForColdRestart()
    }

    /// V9_49 calls this while the authentic interrupted original is still
    /// current, before `beginInterruptedEarly...` poisons its ticket. The
    /// Service supplies the physical baseline from its actual first frame.
    func armPostHandoffHostileFixtureForTesting(
        _ value: EraseRouterOperationV1,
        originalService: EraseAllService
    ) throws {
        try requireEraseRetirementOperation(value)
        let ticket = value.ticket
        guard let state = originalOperations[ticket.operationID],
              let coordinator = state.source.coordinator,
              let subject = state.eraseSubject,
              let reservation = state.acknowledgedReservation,
              reservation.subject == subject,
              state.eraseAuthorizationIssued,
              retainedEraseRetirementOperation === value,
              !value.detached else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let intent = try originalService.interruptedRetiredAuthorityIntentForTesting(
            .afterPointerSwitch, operation: value)
        try requirePreactivationDurableEraseRouteForTesting(
            value, state: state, coordinator: coordinator,
            subject: subject, expectedFault: .afterPointerSwitch,
            originalService: originalService,
            canonicalIntent: intent, poisoned: false)
        let binding = try originalService.capturePostHandoffHostileSourceForTesting(
            operation: value)
        try value.armV949PostHandoffSource(
            service: originalService, subject: subject,
            reservation: reservation, binding: binding)
    }

    /// The returned object is private-minted and one-use. Its source bytes
    /// predate checked handoff; the next fixture owner must acquire *new* EX/G.
    func takePostHandoffHostileFixtureWitnessForTesting(
        _ value: EraseRouterOperationV1
    ) throws -> V949PostHandoffHostileFixtureWitnessV1 {
        guard abandonedOriginalEraseForColdRestart,
              retainedEraseRetirementOperation === value,
              originalOperations[value.ticket.operationID] == nil,
              case .maintenance(.eraseInconsistent) = route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return try value.takeV949PostHandoffWitness()
    }

    func finishNotificationRefusalEraseColdRestartForTesting(
        _ value: EraseRouterOperationV1
    ) throws {
        guard abandonedOriginalEraseForColdRestart,
              retainedEraseRetirementOperation === value,
              case .maintenance(.eraseInconsistent) = route,
              let held = notificationRefusalColdExitForTesting,
              held.operation === value else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try value.finishInterruptedOriginalPreparationForColdRestart {
            try held.service
                .requireOriginalNotificationReadbackRefusalForColdExitForTesting(
                    operation: value, subject: held.subject)
        }
    }
#endif

    fileprivate func requireLiveEraseService(_ value: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator) throws {
        try requireEraseRetirementOperation(value)
        let state = try awaitlessValidateEraseTicket(value.ticket)
        guard state.source.coordinator === coordinator,
              operationOwnedWriter?.coordinator === coordinator,
              state.sourceGenerationID == coordinator.generationID,
              temporalNormalizationOperation == nil, temporalColdOperation == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    fileprivate func requireLiveEraseRecovery(_ value: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator) throws {
        try requireEraseRetirementOperation(value)
        let state = try awaitlessValidateEraseTicket(value.ticket)
        guard state.source.coordinator === coordinator,
              operationOwnedWriter?.coordinator === coordinator,
              state.acknowledgedReservation != nil,
              temporalNormalizationOperation == nil, temporalColdOperation == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    fileprivate func originalEraseRecoverySubject(_ value: EraseRouterOperationV1)
        throws -> EraseAllOperationSubjectV1? {
        try requireEraseRetirementOperation(value)
        let state = try awaitlessValidateEraseTicket(value.ticket)
        guard state.acknowledgedReservation?.subject == state.eraseSubject else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return state.eraseSubject
    }

    fileprivate func eraseRetirementBinding(_ value: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator) throws -> EraseRetirementBindingV1 {
        try requireEraseTransferSource(value, coordinator: coordinator)
        guard let state = originalOperations[value.ticket.operationID], let subject = state.eraseSubject,
              state.acknowledgedReservation?.subject == subject else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return try coordinator.eraseRetirementBinding(subject: subject,
            operationID: value.ticket.operationID, ownerMint: state.mint.eraseBindingID)
    }

    func activateErasePreparationSession(_ session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator, operation: EraseRouterOperationV1) throws {
        do {
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=router-target-enter")
#endif
        try requireErasePreparationTarget(operation, session: session, coordinator: coordinator)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=router-target-complete")
#endif
        guard pendingWriterLeaseReleases.isEmpty, pendingCoordinatorReleases.isEmpty,
              preparedStartup == nil, publishedWriter == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        #if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=router-factory-capture-enter")
        #endif
        let capturedFactory = try generationFactory.capturingEraseReaders(in: operation.inventory)
        #if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=router-factory-capture-complete")
            print("ORIGINAL_ACTIVATION_V1 stage=router-ordinary-view-enter")
        #endif
        let ordinaryFactory = try capturedFactory.ordinaryViewForErasePreparation(
            operation: operation, session: session, coordinator: coordinator)
        #if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=router-ordinary-view-complete")
            print("ORIGINAL_ACTIVATION_V1 stage=router-coordinator-enter")
        #endif
            try coordinator.activateForOriginalEraseUnderRetainedExclusion(
                session: session, generationFactory: ordinaryFactory,
                operation: operation)
        #if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=router-coordinator-complete")
        #endif
        let owner = OwnedWriter(coordinator)
        operationOwnedWriter = owner
        pendingErasedActivation = (owner, session, operation.ticket.operationID)
        deferredEraseCoordinator = nil
        route = .checking
        } catch {
#if DEBUG
            if let failure = error as? WorkspaceMutationFailureV1 {
                switch failure {
                case .writerInvalidated:
                    print("ORIGINAL_ACTIVATION_V1 error=writer-invalidated")
                case .wrongWriterInstance:
                    print("ORIGINAL_ACTIVATION_V1 error=wrong-writer-instance")
                case .wrongWorkspace:
                    print("ORIGINAL_ACTIVATION_V1 error=wrong-workspace")
                case .wrongGeneration:
                    print("ORIGINAL_ACTIVATION_V1 error=wrong-generation")
                case .staleWorkspaceRevision:
                    print("ORIGINAL_ACTIVATION_V1 error=stale-workspace-revision")
                case .staleEntityRevision:
                    print("ORIGINAL_ACTIVATION_V1 error=stale-entity-revision")
                case .mutationIDQuarantined:
                    print("ORIGINAL_ACTIVATION_V1 error=mutation-id-quarantined")
                case .idempotencyCapacityReached:
                    print("ORIGINAL_ACTIVATION_V1 error=idempotency-capacity")
                case .revisionOverflow:
                    print("ORIGINAL_ACTIVATION_V1 error=revision-overflow")
                case .unsupportedCommand:
                    print("ORIGINAL_ACTIVATION_V1 error=unsupported-command")
                case .invalidCommand:
                    print("ORIGINAL_ACTIVATION_V1 error=invalid-command")
                case .invalidEnvelope:
                    print("ORIGINAL_ACTIVATION_V1 error=invalid-envelope")
                case .invalidReceipt:
                    print("ORIGINAL_ACTIVATION_V1 error=invalid-receipt")
                case .invalidReversal:
                    print("ORIGINAL_ACTIVATION_V1 error=invalid-reversal")
                case .receiptHistoryCorrupt:
                    print("ORIGINAL_ACTIVATION_V1 error=receipt-history-corrupt")
                case .sequenceCollision:
                    print("ORIGINAL_ACTIVATION_V1 error=sequence-collision")
                case .storageAdmissionFailed:
                    print("ORIGINAL_ACTIVATION_V1 error=storage-admission")
                case .persistenceFailed:
                    print("ORIGINAL_ACTIVATION_V1 error=persistence-failed")
                }
            } else {
                print("ORIGINAL_ACTIVATION_V1 error=other")
            }
#endif
            throw error
        }
    }

    fileprivate func requireErasePreparationTarget(_ value: EraseRouterOperationV1,
        session: StoreGenerationSession, coordinator: StoreSessionCoordinator) throws {
        try requireLiveEraseRecovery(value, coordinator: coordinator)
        guard let state = originalOperations[value.ticket.operationID], let subject = state.eraseSubject,
              state.acknowledgedReservation?.subject == subject,
              session.generationID == subject.newGenerationID,
              subject.applicationSupportURL.standardizedFileURL == applicationSupportURL.standardizedFileURL,
              try generationFactory.currentGenerationID() == session.generationID else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    fileprivate func requireEraseTransferSource(_ value: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator) throws {
        try requireEraseRetirementOperation(value)
        let state = try awaitlessValidateEraseTicket(value.ticket)
        guard state.source.coordinator === coordinator, temporalNormalizationOperation == nil,
              temporalColdOperation == nil, pendingCoordinatorReleases.isEmpty,
              pendingWriterLeaseReleases.isEmpty, preparedStartup == nil,
              publishedWriter == nil,
              operationOwnedWriter?.coordinator === coordinator,
              pendingErasedActivation?.owner.coordinator === coordinator else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    fileprivate func detachEraseAggregate(_ value: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator) throws {
        try requireEraseTransferSource(value, coordinator: coordinator)
        guard let retirement = value.retirement else { throw AppAccessContractFailureV1.staleAttempt }
        detachedEraseRetirement = retirement
        operationOwnedWriter = nil
        pendingErasedActivation = nil
        deferredEraseCoordinator = nil
        maintenanceEraseSession = nil
        maintenanceRestoreSession = nil
        pendingEraseDrainProof = nil
        eraseCleanupRetirement = nil
        route = .eraseCleanupPending(.retiring(value))
    }
}

extension StartupRouter {
    /// Called after lifecycle adoption of this operation's authentic receipt.
    /// Construction/publication requires a fresh real startup token; physical
    /// retirement ownership remains intact across denied/inactive executions.
    func finishRetiredEraseActivation(_ value: EraseRouterOperationV1,
        accessGate: AppAccessGateV1) async throws {
        try requireEraseRetirementOperation(value)
        let (retirement, proof, receipt) = try value.completedRetirement()
        let ticket = value.ticket
        guard receipt != nil, detachedEraseRetirement === retirement,
              var state = originalOperations[ticket.operationID],
              state.acknowledgedReservation == receipt?.reservation else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        guard operationID == nil || operationID == ticket.operationID else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        operationID = ticket.operationID
        operationKind = .erase
        isRunning = true
        let executionID = UUID()
        state.postAdoptionStartup = true
        state.postAdoptionExecutionID = executionID
        originalOperations[ticket.operationID] = state
        do {
            await beforePostAdoptionContentRead(executionID)
            try requireCurrentPostAdoptionClaim(operation: ticket.operationID,
                ticket: ticket, executionID: executionID)
            let token = try await accessGate.beginContentRead(for: .startupRecovery)
            try await accessGate.validateContentRead(token, for: .startupRecovery)
            try requireCurrentPostAdoptionClaim(operation: ticket.operationID,
                ticket: ticket, executionID: executionID)
            let profiles = try lifecycleProfileRegistry ?? WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
            let fresh: EraseFreshAdoptionOwnerV1
            if let retained = freshEraseAdoption {
                guard retained.retirement === retirement, retained.proof === proof else {
                    throw AppAccessContractFailureV1.staleAttempt
                }
                fresh = retained
                if fresh.phase == .failed || fresh.phase == .disposing {
                    try fresh.disposeFailedConstruction()
                }
                if fresh.phase == .disposed {
                    try fresh.restartAfterSuccessfulDisposal(executionID: executionID, token: token)
                } else if fresh.phase == .registered {
                    try fresh.authorizeUnstartedExecution(executionID: executionID, token: token)
                }
            } else {
                let actualFactory = try generationFactory.freshForEraseAdoption(retirement: proof)
                fresh = EraseFreshAdoptionOwnerV1(router: self, ticket: ticket,
                    retirement: retirement, proof: proof, executionID: executionID,
                    token: token, factory: actualFactory)
                freshEraseAdoption = fresh // before any new namespace/lease/model effect
            }
            if fresh.phase == .registered { try fresh.construct(lifecycleProfileRegistry: profiles) }
            guard let session = fresh.readySession, let coordinator = fresh.readyCoordinator,
                  let ordinaryFactory = fresh.ordinaryFactory else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            try fresh.requireReadyForPublication(session: session, coordinator: coordinator, factory: ordinaryFactory)
            let owner = OwnedWriter(coordinator)
            let execution = PostAdoptionExecution(ticket: ticket, executionID: executionID, contentReadToken: token)
            try token.withContentRead(for: .startupRecovery) {
                try requireCurrentPostAdoptionClaim(operation: ticket.operationID,
                    ticket: ticket, executionID: executionID)
                generationFactory = ordinaryFactory
                operationAuthorization = .content(accessGate, token)
                operationOwnedWriter = owner
                pendingErasedActivation = (owner, session, ticket.operationID)
                route = .checking
            }
            let completed = await finishErasedSessionActivationCore(session, coordinator: coordinator,
                postAdoptionExecution: execution) {
                    try await accessGate.completePostEraseStartup(token)
                }
            guard completed, case let .ready(actual, _, _) = route, actual === coordinator,
                  originalOperations[ticket.operationID] == nil else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        } catch {
            suspendPostAdoptionExecutionIfCurrent(operation: ticket.operationID,
                ticket: ticket, executionID: executionID)
            throw error
        }
    }
}

extension StartupRouter {
    func resumeOriginalErasePreparation(_ value: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator) throws {
        try requireEraseRetirementOperation(value)
        guard !value.detached, operationID == nil || operationID == value.ticket.operationID,
              let state = originalOperations[value.ticket.operationID],
              state.source.coordinator === coordinator,
              operationOwnedWriter?.coordinator === coordinator else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        operationID = value.ticket.operationID
        operationKind = .erase
        isRunning = true
        operationAuthorization = nil // reservation, never resurrected content token
        route = .checking
    }
}

extension StartupRouter {
    func requireEraseAbortResourcesSettled(_ value: EraseRouterOperationV1) throws {
        try requireEraseRetirementOperation(value)
        try value.requireNoRetirementResourcesForAbort()
    }
}


/// The one cold target validation resumption is bound to the original
/// captured controls and generation inventory. It contains values only; all
/// descriptor and lease authority remains on the same retained operation.
@MainActor
struct EraseSchema2ColdTargetContinuationV1 {
    let observed: EraseColdExistingControlObservationV1.Snapshot
    let intent: EraseIntentV1
    let generation: EraseSchema2ColdTargetSnapshotV1
    let operationsNames: Set<String>
    let registryTokens: [GenerationLeaseTokenV1]?
}

/// One pointer-switched preactivation retry uses the first observed control
/// frame and target cut. The attempt and all actual descriptors stay on the
/// retained operation; this value cannot authorize a fresh source capture.
@MainActor
struct EraseSchema2ColdPreactivationContinuationV1 {
    let observed: EraseColdExistingControlObservationV1.Snapshot
    let intent: EraseIntentV1
    let preparation: ErasePreparationV2
    let generation: EraseSchema2ColdTargetSnapshotV1
    let operationsNames: Set<String>
    let registryTokens: [GenerationLeaseTokenV1]
}

/// A first authenticated R cut is not a P retry. Its exact target-current,
/// final-retired and displaced P temporary facts are frozen before any
/// private target read or new reader publication. The retained operation,
/// rather than this value, owns EX/G and every descriptor.
@MainActor
struct EraseSchema2ColdActivatedEntryContinuationV1 {
    let observed: EraseColdExistingControlObservationV1.Snapshot
    let intent: EraseIntentV1
    let preparation: ErasePreparationV2
    let generation: EraseSchema2ColdTargetSnapshotV1
    let operationsNames: Set<String>
    let registryTokens: [GenerationLeaseTokenV1]
    let phaseCut: EraseIntentStore.Schema2ColdPhaseCASCutV1
    /// A first R cut with a durable prospective roster replays the exact
    /// recorded survivor prefix. It cannot manufacture a validated old tree
    /// after a prior unlink removed model.sqlite.
    let replayRoster: EraseSchema2ColdDeletionRosterV1?
}

@MainActor
struct EraseSchema2ColdTargetReaderAdmissionV1 {
    enum Stage: Equatable {
        case pointerPreactivation, activatedEntry, activatedRosterReplay
    }
    let stage: Stage
    let intent: EraseIntentV1
    let preparation: ErasePreparationV2
    let targetSnapshot: EraseSchema2ColdTargetSnapshotV1
    let priorTokens: [GenerationLeaseTokenV1]
}

/// One original-source private validation retry bound to the first genuine
/// schema-2 cold observation. This carries values only; the retained operation
/// owns the actual Support EX, Registry G, control, manifest, source and copy.
@MainActor
struct EraseSchema2ColdOriginalContinuationV1 {
    let observed: EraseColdExistingControlObservationV1.Snapshot
    let intent: EraseIntentV1
    let preparation: ErasePreparationV2
    let generation: EraseSchema2ColdTargetSnapshotV1
    let operationsNames: Set<String>
    let registryTokens: [GenerationLeaseTokenV1]
    let phaseCut: EraseIntentStore.Schema2ColdPhaseCASCutV1?
}

/// A complete first-name-set partition and its actual G census remain on
/// the operation across each retired private-copy await. No source or token
/// may be reconstructed from this value on retry.
@MainActor
struct EraseSchema2ColdRetiredContinuationV1 {
    let observed: EraseColdExistingControlObservationV1.Snapshot
    let intent: EraseIntentV1
    let preparation: ErasePreparationV2
    let generation: EraseSchema2ColdTargetSnapshotV1
    let operationsNames: Set<String>
    let registryTokens: [GenerationLeaseTokenV1]
    let phaseCut: EraseIntentStore.Schema2ColdPhaseCASCutV1?
}

/// The complete typed tree returned by the same held old source after its
/// private semantic validation. This value is retained on the cold operation
/// while the physical root descriptor remains open; neither a later scan nor
/// a copied generation can replace the pre-effect deletion witness.
@MainActor
struct EraseSchema2ColdValidatedOriginalTreeV1 {
    let intent: EraseIntentV1
    let preparation: ErasePreparationV2
    let digest: String
    let nodes: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]
}

/// Actual startup ownership before the first cold Erase reader is allocated.
/// No original Erase ticket or completed receipt is manufactured here.
@MainActor
final class EraseColdPreparationOperationV1 {
    fileprivate weak var router: StartupRouter?
    fileprivate let operationID: UUID
    private var authorization: StartupRouter.StartupAuthorization
    fileprivate var executionID: UUID
    private let ownerMint = UUID()
    private(set) var inventory = EraseReaderRetirementInventoryV1()
    private var inventoryBound = false
    private var settledWitnesses: [EraseColdPreparationFailureDrainWitnessV1] = []
    private var rollback: EraseColdPreparationRollbackV1?
    private let factory: StoreGenerationFactory
    private var registry: GenerationLeaseRegistryV1?
    private var c05ColdRegistryConstruction: EraseC05ColdRegistryConstructionV1?
    private var c05ColdWriterActivities: [EraseC05ColdWriterActivityAcquisitionV1] = []
    private var c05ColdWriterAllocation: EraseC05ColdWriterAllocationV1?
    private var c05ColdRegistryObservations: [EraseC05ColdRegistryObservationAttemptV1] = []
    private var c05ColdPredecessorProbe: EraseC05ColdPredecessorProbeV1?
    private var c05ColdPredecessorReplacement: EraseC05ColdPredecessorReplacementV1?
    private var c05ColdPredecessorCheckedComplete = false
    private var frozenC05ManifestReader: EraseC05FrozenManifestReaderV1?
    private var c05ColdJournalReader: EraseC05ColdPreparationJournalReaderV1?
    private var coldControlObservation: EraseColdExistingControlObservationV1?
    private var emptyNoWorkObservation: EraseColdExistingControlObservationV1.Snapshot?
    private var coldControlObservationClosed = false
    private var schema2ColdIntentStore: EraseIntentStore?
    private var schema2ColdIntentStoreClosed = false
    private var schema2ColdManifestOwner: EraseSchema2ColdManifestOwnerV1?
    private var schema2ColdManifestOwnerClosed = false
    private var schema2ColdTargetSource:
        EraseSchema2ColdTargetSourceV1?
    private var schema2ColdTargetSourceClosed = false
    private(set) var schema2ColdRetainedOriginalSource:
        EraseSchema2ColdRetainedSourceV1?
    private var schema2ColdRetainedOriginalSourceClosed = false
    private(set) var schema2ColdPrivateSourceAttempt:
        EraseSchema2ColdPrivateSourceAttemptV1?
    private var schema2ColdOriginalContinuation:
        EraseSchema2ColdOriginalContinuationV1?
    private var schema2ColdOriginalValidationComplete = false
    private var schema2ColdValidatedOriginalTree:
        EraseSchema2ColdValidatedOriginalTreeV1?
    private var schema2ColdRetiredSources:
        [UUID: EraseSchema2ColdRetiredSourceV1]?
    private var schema2ColdRetiredContinuation:
        EraseSchema2ColdRetiredContinuationV1?
    private var schema2ColdRetiredPrivateAttempts:
        [UUID: EraseSchema2ColdPrivateSourceAttemptV1] = [:]
    private var schema2ColdValidatedGenerationTrees:
        [UUID: EraseSchema2ColdValidatedGenerationTreeV1]?
    private var schema2ColdFirstAbsentGenerationIDs: Set<UUID>?
    private var schema2ColdOriginalTokenCensus: [GenerationLeaseTokenV1]?
    // This is only a retained P semantic observation. Target-private and
    // auxiliary physical projections are separately required before replay.
    private var schema2ColdOriginalRetiredSemantic:
        EraseSchema2ColdManifestOwnerV1
            .OriginalRetiredSemanticObservationV1?
    // Retain the first observer before any borrowed auxiliary descriptor read.
    private var schema2ColdAuxiliaryFirstObserver:
        EraseSchema2ColdAuxiliaryFirstObserverV1?
    private var schema2ColdAuxiliaryFirstSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var schema2ColdAuxiliaryRosterCapture:
        EraseSchema2ColdAuxiliaryRosterCaptureV1?
    private var schema2ColdAuxiliaryRosterSeal:
        EraseSchema2ColdAuxiliaryRosterPublicationSealV1?
    private var schema2ColdPreparedOriginalAuxiliaryObservation:
        EraseSchema2ColdManifestOwnerV1
            .PreparedOriginalAuxiliaryObservationV1?
    private var schema2ColdOriginalManifestDigest: String?
    private var schema2ColdOriginalGenerationID: UUID?
    private(set) var schema2ColdTargetValidationAttempt:
        EraseSchema2ColdTargetValidationAttemptV1?
    private(set) var schema2ColdPreparedTargetValidationAttempt:
        EraseSchema2ColdTargetValidationAttemptV1?
    private var schema2ColdPreparedTargetPrivateValidated = false
    private var schema2ColdPreactivationSnapshot:
        EraseSchema2ColdTargetSnapshotV1?
    private var schema2ColdTargetPointerPublished = false
    private var schema2ColdFinalRetiredPublished = false
    private(set) var schema2ColdActivatedTargetAttempt:
        EraseSchema2ColdActivatedTargetAttemptV1?
    private var schema2ColdTargetReaderAllocation:
        GenerationLeaseAllocationAttemptV1?
    private var schema2ColdTargetReaderAdmission:
        EraseSchema2ColdTargetReaderAdmissionV1?
    private var schema2ColdTargetReaderHandle:
        GenerationLeaseHandleV1?
    private var schema2ColdTargetReaderTokenCensus:
        [GenerationLeaseTokenV1]?
    private var schema2ColdActivatedTargetSession:
        StoreGenerationSession?
    private var schema2ColdPointerPhasePublished = false
    private var schema2ColdPublishedIntent: EraseIntentV1?
    private var schema2ColdRosterPublished = false
    private var schema2ColdRosterPublicationSeal:
        EraseSchema2ColdDeletionRosterPublicationSealV1?
    private var schema2ColdRosterFirstIntent: EraseIntentV1?
    private var schema2ColdRosterFirstPreparation: ErasePreparationV2?
    private var schema2ColdPublishedRoster:
        EraseSchema2ColdDeletionRosterV1?
    private var schema2ColdNotificationSource:
        EraseSchema2ColdNotificationSourceV1?
    private var schema2ColdNotificationControl:
        (any Schema2ColdNotificationEraseControlV1)?
    private var schema2ColdNotificationDrainReceipt:
        EraseSchema2ColdNotificationDrainReceiptV1?
    private var schema2ColdObservedReplayRoster:
        EraseSchema2ColdDeletionRosterV1?
    private var schema2ColdDeletionExecutor:
        EraseSchema2ColdCheckedDeletionExecutorV1?
    private var schema2ColdDeletionSourcesClosed = false
    private enum Schema2ColdTargetLiveOpenState: Equatable {
        case idle, inFlight, settled
    }
    private var schema2ColdTargetLiveOpenState:
        Schema2ColdTargetLiveOpenState = .idle
    private var schema2ColdTargetContinuation:
        EraseSchema2ColdTargetContinuationV1?
    private var schema2ColdPreactivationContinuation:
        EraseSchema2ColdPreactivationContinuationV1?
    private var schema2ColdActivatedEntryContinuation:
        EraseSchema2ColdActivatedEntryContinuationV1?
    private var schema2ColdActivatedEntryValidated = false
    private var schema2ColdActivatedEntryTempSettled = false
    private var schema2ColdPhysicalExclusion: EraseSchema2ColdPhysicalExclusionV1?
    private var schema2ColdPhysicalExclusionClosed = false
    private var schema2ColdSupportIdentity: (device: dev_t, inode: ino_t)?
    private var schema2ColdRegistryConstruction: TemporalColdRegistryConstructionV1?
    private var schema2ColdActivityAcquisition:
        GenerationTemporalColdActivityAcquisitionV1?
    private var schema2ColdActivity: GenerationTemporalActivityHandleV1?
    private var schema2ColdRegistryObservations:
        [EraseSchema2ColdRegistryObservationAttemptV1] = []
    private var schema2ColdGuardProbes:
        [EraseSchema2ColdGuardProbeV1] = []
    private var c05ColdJobStore: LocalJobStoreV1?
    /// One real cold producer is retained before its first store observation.
    /// A failed effect or uncertain close keeps the same actor fenced here.
    private var c05ColdRunner: ResumableLocalJobRunnerV1?
    private var c05ColdSourceDrainWitness: EraseC05ColdSourceDrainWitnessV1?
    private var c05ColdJournalReaderClosed = false
    private var frozenC05PointerReader: EraseC05FrozenPointerReaderV1?
    private var frozenC05PointerReaderClosed = false
    private var frozenC05ManifestReaderClosed = false
    private var serviceFrame = false
    private var admissionSealed = false
    private var retirementAcquisitionStarted = false
    private var failureWitness: EraseColdPreparationFailureDrainWitnessV1?
    private var prepared: EraseCleanupAfterRetirementV1?
    private var preparedIntentStore: EraseIntentStore?
    private var preparedIntent: EraseIntentV1?
    private var drain: EraseSessionDrainWitnessV1?
    private var coldAuthority: EraseColdRetirementAuthorityV1?
    private var exclusion: EraseRetirementExclusionV1?
    private var retirement: EraseSessionRetirementV1?
    private var detached = false
    private var advancingCleanup = false

    fileprivate init(router: StartupRouter, operationID: UUID,
        authorization: StartupRouter.StartupAuthorization, factory: StoreGenerationFactory) {
        self.router = router; self.operationID = operationID; self.executionID = operationID
        self.authorization = authorization; self.factory = factory
    }

    /// Continuation receives an actual new startup execution, never a new
    /// operation identity or newly reconstructed resource owner.
    fileprivate func resume(executionID: UUID, authorization: StartupRouter.StartupAuthorization) throws {
        guard let router, !serviceFrame, !advancingCleanup else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireRetainedColdPreparation(self)
        self.executionID = executionID
        self.authorization = authorization
        try requireLive()
    }

    func bindValidatedTarget(subject: EraseAllOperationSubjectV1,
        session: StoreGenerationSession) throws -> EraseRetirementBindingV1 {
        try requireLive()
        guard serviceFrame, !admissionSealed, let registry,
              subject.applicationSupportURL == factory.restoreApplicationSupportURL.standardizedFileURL,
              subject.newGenerationID == session.generationID,
              let epoch = session.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try inventory.capture(session)
        var support = stat(), operations = stat()
        guard Darwin.lstat(subject.applicationSupportURL.path, &support) == 0,
              support.st_mode & S_IFMT == S_IFDIR,
              Int64(support.st_dev) == subject.applicationSupportDevice,
              UInt64(support.st_ino) == subject.applicationSupportInode,
              Darwin.lstat(subject.applicationSupportURL.appendingPathComponent("FieldEvidenceOperations").path,
                  &operations) == 0, operations.st_mode & S_IFMT == S_IFDIR else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let identity = StreamingArchiveRootIdentityV1(device: UInt64(operations.st_dev), inode: UInt64(operations.st_ino))
        try registry.requireTemporalEraseNamespace(identity)
        return EraseRetirementBindingV1(subject: subject, operationID: operationID,
            ownerMint: ownerMint, registryIdentity: identity, generationEpoch: epoch,
            workspaceIdentity: session.workspaceIdentity)
    }

    func retainPrepared(_ value: EraseCleanupAfterRetirementV1,
        intentStore: EraseIntentStore, intent: EraseIntentV1) throws {
        try requireLive()
        guard serviceFrame, !admissionSealed, prepared == nil,
              registry != nil, value.binding.operationID == operationID,
              value.binding.ownerMint == ownerMint else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        prepared = value
        preparedIntentStore = intentStore
        preparedIntent = intent
        try finishPreparedRegistration()
    }

    /// Replays only the already retained preparation; it never constructs
    /// another target session after a post-preparation failure.
    private func finishPreparedRegistration() throws {
        try requireLive()
        guard let router, let prepared, let registry,
              let preparedIntentStore, let preparedIntent else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if drain == nil {
            drain = try inventory.seal(binding: prepared.binding)
            admissionSealed = true
        }
        guard let drain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if coldAuthority == nil {
            coldAuthority = try router.prepareColdEraseRetirement(binding: prepared.binding,
                registry: registry, drain: drain, intentStore: preparedIntentStore, intent: preparedIntent)
        }
    }

    fileprivate func validateRetirementAccess() async throws {
        try requireLive()
        guard !serviceFrame, admissionSealed, retirementAcquisitionStarted,
              prepared != nil, drain != nil else { throw AppAccessContractFailureV1.staleAttempt }
        try await authorization.validate()
        try requireLive()
        guard !serviceFrame, admissionSealed, retirementAcquisitionStarted else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    func requireStartupContinuation() throws {
        try requireLive()
        try authorization.withMediaRecovery { try requireLive() }
    }

    fileprivate func withRetirementAccess<T>(_ body: () throws -> T) throws -> T {
        try requireLive()
        guard !serviceFrame, admissionSealed, retirementAcquisitionStarted else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return try authorization.withMediaRecovery(body)
    }

    func advancePreparedCleanup() async throws -> Bool {
        try requireLive()
        guard !serviceFrame, !advancingCleanup else { throw AppAccessContractFailureV1.staleAttempt }
        advancingCleanup = true
        defer { advancingCleanup = false }
        try requireStartupContinuation()
        try finishPreparedRegistration()
        guard let prepared, let drain, let coldAuthority else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if exclusion == nil {
            // Monotonic before first lock attempt. Ordinary failure disposal
            // is forbidden even when acquisition throws before returning EX.
            retirementAcquisitionStarted = true
            exclusion = try await coldAuthority.acquire()
            try requireStartupContinuation()
        }
        guard let exclusion else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if !detached {
            retirement = try prepared.retainTransferredExclusion(exclusion, drain: drain)
            try coldAuthority.sealForRetirement(exclusion: exclusion)
            detached = true
        }
        let completed = try await prepared.advance()
        try requireStartupContinuation()
        return completed
    }

    fileprivate var hasPreparedCleanup: Bool { prepared != nil }
    fileprivate var hasRollback: Bool { rollback != nil }
    fileprivate var hasEmptyNoWorkObservation: Bool { emptyNoWorkObservation != nil }

    fileprivate func requireNoWork() throws {
        guard !serviceFrame, !advancingCleanup, prepared == nil, rollback == nil,
              !retirementAcquisitionStarted,
              schema2ColdIntentStore == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if coldControlObservation != nil && !coldControlObservationClosed {
            guard emptyNoWorkObservation != nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        try inventory.requireNoConstructedResourcesForAbort()
    }

    fileprivate func completedRetirement() throws -> (EraseSessionRetirementV1, ErasedRegistryRetirementProofV1) {
        guard let router, !serviceFrame, detached, let prepared, let retirement,
              let proof = prepared.proof, retirement.ownsProof(proof) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireRetainedColdPreparation(self)
        // The actual cleanup object checks its terminal release phase. Cold
        // cleanup has no adoption reservation and must not create a receipt.
        guard try prepared.completedReceipt() == nil else { throw EraseAllServiceError.invalidAuthority }
        return (retirement, proof)
    }

    fileprivate func requireCompletedRetirement(_ expected: EraseSessionRetirementV1,
        proof expectedProof: ErasedRegistryRetirementProofV1) throws {
        let actual = try completedRetirement()
        guard actual.0 === expected, actual.1 === expectedProof else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func configuredFactory() throws -> StoreGenerationFactory {
        try requireLive()
        if !inventoryBound {
            try inventory.bindColdPreparation(operation: self)
            inventoryBound = true
        }
        return try factory.capturingEraseReaders(in: inventory)
    }

    func retainC05ColdJournalReader(
        _ reader: EraseC05ColdPreparationJournalReaderV1
    ) throws {
        try requireLive()
        guard serviceFrame, !admissionSealed,
              c05ColdJournalReader == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdJournalReader = reader
    }

    func retainColdControlObservation(
        _ observation: EraseColdExistingControlObservationV1
    ) throws {
        try requireServiceAccess()
        guard coldControlObservation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        coldControlObservation = observation
    }

    func requireColdControlObservation(
        _ observation: EraseColdExistingControlObservationV1
    ) throws {
        try requireServiceAccess()
        guard coldControlObservation === observation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func closeColdControlObservationChecked() throws {
        try requireServiceAccess()
        guard !coldControlObservationClosed, let coldControlObservation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try coldControlObservation.closeChecked()
        coldControlObservationClosed = true
    }

    func retainSchema2ColdIntentStore(_ store: EraseIntentStore) throws {
        try requireServiceAccess()
        guard schema2ColdIntentStore == nil,
              coldControlObservation != nil,
              !coldControlObservationClosed,
              emptyNoWorkObservation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdIntentStore = store
    }

    func retainSchema2ColdManifestOwner(
        _ owner: EraseSchema2ColdManifestOwnerV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdIntentStore != nil,
              !schema2ColdIntentStoreClosed,
              schema2ColdManifestOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Retain before the first Factory/manifest descriptor is opened.
        schema2ColdManifestOwner = owner
    }

    func retainSchema2ColdPhysicalExclusion(
        _ owner: EraseSchema2ColdPhysicalExclusionV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdIntentStore != nil,
              !schema2ColdIntentStoreClosed,
              schema2ColdPhysicalExclusion == nil,
              !schema2ColdPhysicalExclusionClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdPhysicalExclusion = owner
    }

    func requireSchema2ColdPhysicalExclusion(
        _ owner: EraseSchema2ColdPhysicalExclusionV1
    ) throws {
        try requireLive()
        guard schema2ColdPhysicalExclusion === owner,
              !schema2ColdPhysicalExclusionClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func bindSchema2ColdPhysicalExclusion(
        _ owner: EraseSchema2ColdPhysicalExclusionV1,
        device: dev_t, inode: ino_t
    ) throws {
        try requireSchema2ColdPhysicalExclusion(owner)
        guard schema2ColdSupportIdentity == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try owner.requireHeld(expectedDevice: device,
            expectedInode: inode)
        schema2ColdSupportIdentity = (device, inode)
    }

    func closeSchema2ColdPhysicalExclusionAfterFailureChecked() throws {
        try requireServiceAccess()
        guard let schema2ColdPhysicalExclusion,
              !schema2ColdPhysicalExclusionClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Mark terminal before an unlock/close whose failure is ambiguous.
        schema2ColdPhysicalExclusionClosed = true
        try schema2ColdPhysicalExclusion.closeAfterFailureChecked()
    }

    func retainSchema2ColdRegistryConstruction(
        _ construction: TemporalColdRegistryConstructionV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdPhysicalExclusion != nil,
              !schema2ColdPhysicalExclusionClosed,
              schema2ColdSupportIdentity != nil,
              schema2ColdRegistryConstruction == nil,
              registry == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdRegistryConstruction = construction
    }

    func requireSchema2ColdRegistryConstruction() throws {
        try requireServiceAccess()
        guard schema2ColdPhysicalExclusion != nil,
              !schema2ColdPhysicalExclusionClosed,
              schema2ColdSupportIdentity != nil,
              schema2ColdRegistryConstruction != nil,
              registry == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// Synchronous transfer after the no-repair constructor has transferred
    /// its FDs. The construction is already retained on this operation.
    func retainConstructedSchema2ColdRegistry(
        _ value: GenerationLeaseRegistryV1
    ) {
        registry = value
    }

    func requireConstructedSchema2ColdRegistry(
        _ expected: GenerationLeaseRegistryV1
    ) throws {
        try requireLive()
        guard schema2ColdRegistryConstruction != nil,
              let schema2ColdPhysicalExclusion,
              let schema2ColdSupportIdentity,
              !schema2ColdPhysicalExclusionClosed,
              registry === expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try schema2ColdPhysicalExclusion.requireHeld(
            expectedDevice: schema2ColdSupportIdentity.device,
            expectedInode: schema2ColdSupportIdentity.inode)
    }

    func retainSchema2ColdActivityAcquisition(
        _ value: GenerationTemporalColdActivityAcquisitionV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedSchema2ColdRegistry(expected)
        guard schema2ColdActivityAcquisition == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdActivityAcquisition = value
    }

    func requireSchema2ColdActivityAcquisition(
        _ value: GenerationTemporalColdActivityAcquisitionV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedSchema2ColdRegistry(expected)
        guard schema2ColdActivityAcquisition === value else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainSchema2ColdActivity(
        _ value: GenerationTemporalActivityHandleV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedSchema2ColdRegistry(expected)
        guard schema2ColdActivityAcquisition != nil,
              schema2ColdActivity == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdActivity = value
    }

    func retainSchema2ColdRegistryObservation(
        _ value: EraseSchema2ColdRegistryObservationAttemptV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedSchema2ColdRegistry(expected)
        // Only a checked-close result can retire a descriptor attempt. Keep
        // ambiguous closes retained and terminal; each new read still owns a
        // distinct attempt before its descriptor opens.
        schema2ColdRegistryObservations.removeAll { $0.isCheckedClosed }
        guard schema2ColdActivity != nil,
              schema2ColdRegistryObservations.count < 8,
              !schema2ColdRegistryObservations.contains(where: { $0 === value }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdRegistryObservations.append(value)
    }

    func retainSchema2ColdGuardProbe(
        _ value: EraseSchema2ColdGuardProbeV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedSchema2ColdRegistry(expected)
        guard schema2ColdActivity != nil,
              schema2ColdGuardProbes.count < 64,
              !schema2ColdGuardProbes.contains(where: { $0 === value }),
              !schema2ColdGuardProbes.contains(where: {
                  $0.predecessor == value.predecessor
              }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdGuardProbes.append(value)
    }

    func requireSchema2ColdPredecessorGuards(
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedSchema2ColdRegistry(expected)
        for probe in schema2ColdGuardProbes {
            try probe.requireHeldNamed()
        }
    }

    func closeSchema2ColdPredecessorGuardsAfterFailureChecked(
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedSchema2ColdRegistry(expected)
        for probe in schema2ColdGuardProbes where !probe.isCheckedClosed {
            try probe.closeAfterFailureChecked()
        }
    }

    func requireSchema2ColdManifestOwner(
        _ owner: EraseSchema2ColdManifestOwnerV1
    ) throws {
        try requireLive()
        guard schema2ColdManifestOwner === owner,
              !schema2ColdManifestOwnerClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireSchema2ColdOriginalControls(
        intent: EraseIntentV1, preparation: ErasePreparationV2
    ) throws {
        try requireServiceAccess()
        guard let store = schema2ColdIntentStore,
              !schema2ColdIntentStoreClosed,
              let observation = coldControlObservation,
              !coldControlObservationClosed,
              intent.schemaVersion == 2,
              intent.phase == .pointerSwitched ||
                intent.phase == .sessionActivated,
              intent.oldPointer == preparation.oldPointer,
              preparation.c05JobDrainV3 == nil,
              try store.load() == intent,
              try store.loadPreparation() == preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireColdControlObservation(observation)
    }

    /// A prepared intent may already have its genuine target current pointer
    /// after the original pointer effect and before the P→Q intent CAS. Keep
    /// this admission distinct from the R/Q cleanup controls: the first held
    /// pointer cut must be target, and no P old-current source is opened by it.
    func requireSchema2ColdPreparedTargetCurrentControls(
        intent: EraseIntentV1, preparation: ErasePreparationV2
    ) throws {
        try requireServiceAccess()
        guard let store = schema2ColdIntentStore,
              !schema2ColdIntentStoreClosed,
              let observation = coldControlObservation,
              !coldControlObservationClosed,
              let manifest = schema2ColdManifestOwner,
              !schema2ColdManifestOwnerClosed,
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared,
              intent.oldPointer == preparation.oldPointer,
              preparation.matches(intent),
              preparation.c05JobDrainV3 == nil,
              try store.load() == intent,
              try store.loadPreparation() == preparation,
              try manifest.observeAllowedCurrentCut(
                intent: intent, operation: self) == .target else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireColdControlObservation(observation)
        _ = try manifest.requireCurrentTargetPointer(
            intent: intent, operation: self)
    }

    func bindSchema2ColdOriginalTokenCensus(
        _ tokens: [GenerationLeaseTokenV1],
        registry expected: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1
    ) throws {
        try requireServiceAccess()
        try requireConstructedSchema2ColdRegistry(expected)
        guard let store = schema2ColdIntentStore,
              let intent = try store.load(),
              let preparation = try store.loadPreparation(),
              let oldPointer = intent.oldPointer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if intent.phase == .emptyGenerationPrepared {
            try requireSchema2ColdPreparedTargetCurrentControls(
                intent: intent, preparation: preparation)
        } else {
            try requireSchema2ColdOriginalControls(
                intent: intent, preparation: preparation)
        }
        guard schema2ColdActivity === activity,
              schema2ColdOriginalTokenCensus == nil,
              schema2ColdOriginalManifestDigest == nil,
              schema2ColdOriginalGenerationID == nil,
              schema2ColdRetainedOriginalSource == nil,
              tokens.allSatisfy({ token in
                  token.epoch.generationID != intent.oldGenerationID
                      || token.epoch.generationManifestSHA256
                          == oldPointer.generationManifestSHA256
              }),
              try expected.observeEraseSchema2ColdRegistry(
                operation: self, activity: activity) == tokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPredecessorGuards(registry: expected)
        schema2ColdOriginalTokenCensus = tokens
        schema2ColdOriginalManifestDigest =
            oldPointer.generationManifestSHA256
        schema2ColdOriginalGenerationID = intent.oldGenerationID
    }

    func requireSchema2ColdOriginalAuthority() throws {
        try requireServiceAccess()
        guard let expected = schema2ColdOriginalTokenCensus,
              let oldDigest = schema2ColdOriginalManifestDigest,
              let oldID = schema2ColdOriginalGenerationID,
              let registry, let activity = schema2ColdActivity,
              let manifest = schema2ColdManifestOwner,
              !schema2ColdManifestOwnerClosed,
              let exclusion = schema2ColdPhysicalExclusion,
              let identity = schema2ColdSupportIdentity,
              !schema2ColdPhysicalExclusionClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard expected.allSatisfy({ token in
            token.epoch.generationID != oldID
                || token.epoch.generationManifestSHA256 == oldDigest
        }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdManifestOwner(manifest)
        try requireConstructedSchema2ColdRegistry(registry)
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try requireSchema2ColdPredecessorGuards(registry: registry)
        try registry.requireEraseSchema2ColdExcluded(
            operation: self, activity: activity)
        // The value was frozen by bindSchema2ColdOriginalTokenCensus under G;
        // Service reobserves exact tokens before/after private-copy awaits.
        guard schema2ColdOriginalTokenCensus == expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// Data-only first auxiliary capture under the retained EX/G owners.
    func requireSchema2ColdAuxiliaryCaptureAdmission(
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdIntentStore === store,
              schema2ColdManifestOwner === manifest,
              !schema2ColdManifestOwnerClosed,
              let intent = try store.load(),
              let preparation = try store.loadPreparation(),
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared ||
                intent.phase == .pointerSwitched ||
                intent.phase == .sessionActivated,
              preparation.matches(intent),
              let registry, let activity = schema2ColdActivity,
              let tokens = schema2ColdOriginalTokenCensus else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if intent.phase == .emptyGenerationPrepared {
            guard schema2ColdOriginalContinuation?.intent == intent,
                  schema2ColdOriginalContinuation?.preparation == preparation,
                  schema2ColdTargetSource != nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try requireSchema2ColdPreparedTargetCurrentControls(
                intent: intent, preparation: preparation)
        } else {
            try requireSchema2ColdOriginalControls(
                intent: intent, preparation: preparation)
        }
        try requireSchema2ColdOriginalAuthority()
        guard try registry.observeEraseSchema2ColdRegistry(
                operation: self, activity: activity) == tokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireSchema2ColdAuxiliaryCaptureOwner(
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws {
        guard let store = schema2ColdIntentStore,
              schema2ColdManifestOwner === manifest else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdAuxiliaryCaptureAdmission(
            store: store, manifest: manifest)
    }

    func retainSchema2ColdAuxiliaryFirstObserver(
        _ observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws {
        try requireSchema2ColdAuxiliaryCaptureAdmission(
            store: store, manifest: manifest)
        guard schema2ColdAuxiliaryFirstObserver == nil,
              schema2ColdAuxiliaryFirstSnapshot == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdAuxiliaryFirstObserver = observer
    }

    func bindSchema2ColdAuxiliaryFirstObservation(
        _ snapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws {
        guard schema2ColdAuxiliaryFirstObserver === observer,
              schema2ColdAuxiliaryFirstSnapshot == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdAuxiliaryCaptureAdmission(
            store: store, manifest: manifest)
        guard try observer.firstObservation() == snapshot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdAuxiliaryFirstSnapshot = snapshot
    }

    func requireSchema2ColdAuxiliaryFirstObservation(
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws -> (EraseSchema2ColdAuxiliaryFirstObserverV1,
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot) {
        try requireSchema2ColdAuxiliaryCaptureAdmission(
            store: store, manifest: manifest)
        guard let observer = schema2ColdAuxiliaryFirstObserver,
              let snapshot = schema2ColdAuxiliaryFirstSnapshot,
              try observer.firstObservation() == snapshot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return (observer, snapshot)
    }

    /// P's immutable first image may be rechecked on either side of its
    /// private awaits, before the target-private completion latch exists.
    func requireSchema2ColdPreparedAuxiliaryFirstOwner(
        manifest: EraseSchema2ColdManifestOwnerV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1
    ) throws {
        guard let store = schema2ColdIntentStore,
              let intent = try store.load(),
              intent.phase == .emptyGenerationPrepared,
              schema2ColdManifestOwner === manifest else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let first = try requireSchema2ColdAuxiliaryFirstObservation(
            store: store, manifest: manifest)
        guard first.0 === observer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// P-only data admission. This checks the same first auxiliary observer,
    /// original and target private validations, and actual retained EX/G.
    /// It cannot satisfy the Q/R roster or phase effect owners.
    func requireSchema2ColdPreparedAuxiliaryObservationOwner(
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws -> (EraseSchema2ColdAuxiliaryFirstObserverV1,
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot) {
        guard let intent = try store.load(),
              let preparation = try store.loadPreparation(),
              intent.phase == .emptyGenerationPrepared,
              schema2ColdOriginalValidationComplete,
              schema2ColdPreparedTargetPrivateValidated,
              schema2ColdIntentStore === store,
              schema2ColdManifestOwner === manifest,
              let registry, let activity = schema2ColdActivity,
              let tokens = schema2ColdOriginalTokenCensus else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPreparedTargetCurrentControls(
            intent: intent, preparation: preparation)
        try requireSchema2ColdOriginalAuthority()
        let first = try requireSchema2ColdAuxiliaryFirstObservation(
            store: store, manifest: manifest)
        guard try registry.observeEraseSchema2ColdRegistry(
                operation: self, activity: activity) == tokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return first
    }

    func retainSchema2ColdPreparedOriginalAuxiliaryObservation(
        _ value: EraseSchema2ColdManifestOwnerV1
            .PreparedOriginalAuxiliaryObservationV1,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws {
        guard schema2ColdPreparedOriginalAuxiliaryObservation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireSchema2ColdPreparedAuxiliaryObservationOwner(
            store: store, manifest: manifest)
        try value.requireBound(manifest: manifest, store: store,
            operation: self)
        schema2ColdPreparedOriginalAuxiliaryObservation = value
    }

    func retainSchema2ColdAuxiliaryRosterCapture(
        _ capture: EraseSchema2ColdAuxiliaryRosterCaptureV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        snapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        intent: EraseIntentV1, preparation: ErasePreparationV2
    ) throws {
        guard intent.phase == .pointerSwitched,
              let store = schema2ColdIntentStore,
              let manifest = schema2ColdManifestOwner,
              try store.load() == intent,
              try store.loadPreparation() == preparation,
              schema2ColdAuxiliaryFirstObserver === observer,
              schema2ColdAuxiliaryFirstSnapshot == snapshot,
              schema2ColdAuxiliaryRosterCapture == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdAuxiliaryCaptureAdmission(
            store: store, manifest: manifest)
        schema2ColdAuxiliaryRosterCapture = capture
    }

    func requireSchema2ColdAuxiliaryRosterCapture(
        _ capture: EraseSchema2ColdAuxiliaryRosterCaptureV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        snapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        intent: EraseIntentV1, preparation: ErasePreparationV2
    ) throws {
        guard schema2ColdAuxiliaryRosterCapture === capture,
              schema2ColdAuxiliaryFirstObserver === observer,
              schema2ColdAuxiliaryFirstSnapshot == snapshot,
              schema2ColdAuxiliaryRosterSeal == nil,
              let store = schema2ColdIntentStore,
              let manifest = schema2ColdManifestOwner,
              intent.phase == .pointerSwitched,
              try store.load() == intent,
              try store.loadPreparation() == preparation,
              try observer.firstObservation() == snapshot,
              try capture.requireFirst().record.eraseID
                == intent.eraseID.uuidString.lowercased() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdAuxiliaryCaptureAdmission(
            store: store, manifest: manifest)
    }

    func retainSchema2ColdAuxiliaryRosterPublicationSeal(
        _ seal: EraseSchema2ColdAuxiliaryRosterPublicationSealV1,
        store: EraseIntentStore
    ) throws {
        guard schema2ColdAuxiliaryRosterSeal == nil,
              let capture = schema2ColdAuxiliaryRosterCapture,
              let observer = schema2ColdAuxiliaryFirstObserver,
              let snapshot = schema2ColdAuxiliaryFirstSnapshot,
              let manifest = schema2ColdManifestOwner,
              let intent = try store.load(),
              let preparation = try store.loadPreparation(),
              schema2ColdIntentStore === store else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdAuxiliaryRosterCapture(capture,
            observer: observer, snapshot: snapshot,
            intent: intent, preparation: preparation)
        try seal.requireBound(manifest: manifest, operation: self,
            capture: capture, observer: observer, snapshot: snapshot,
            intent: intent, preparation: preparation)
        schema2ColdAuxiliaryRosterSeal = seal
    }

    func requireSchema2ColdOriginalTokenCensus(
        registry expected: GenerationLeaseRegistryV1
    ) throws -> [GenerationLeaseTokenV1] {
        try requireSchema2ColdOriginalAuthority()
        guard registry === expected,
              let tokens = schema2ColdOriginalTokenCensus else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return tokens
    }

    func retainSchema2ColdRetainedSource(
        _ value: EraseSchema2ColdRetainedSourceV1
    ) throws {
        try requireSchema2ColdOriginalAuthority()
        guard schema2ColdRetainedOriginalSource == nil,
              !schema2ColdRetainedOriginalSourceClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Retain before the first old-generation descriptor is opened.
        schema2ColdRetainedOriginalSource = value
    }

    func requireSchema2ColdRetainedSource(
        _ expected: EraseSchema2ColdRetainedSourceV1
    ) throws {
        try requireSchema2ColdOriginalAuthority()
        guard schema2ColdRetainedOriginalSource === expected,
              !schema2ColdRetainedOriginalSourceClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainSchema2ColdPrivateSourceAttempt(
        _ value: EraseSchema2ColdPrivateSourceAttemptV1
    ) throws {
        guard let source = schema2ColdRetainedOriginalSource else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRetainedSource(source)
        guard schema2ColdPrivateSourceAttempt == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdPrivateSourceAttempt = value
    }

    func requireSchema2ColdPrivateSourceAttempt(
        _ expected: EraseSchema2ColdPrivateSourceAttemptV1
    ) throws {
        guard let source = schema2ColdRetainedOriginalSource else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRetainedSource(source)
        guard schema2ColdPrivateSourceAttempt === expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func closeSchema2ColdRetainedSourceChecked() throws {
        guard let source = schema2ColdRetainedOriginalSource,
              let attempt = schema2ColdPrivateSourceAttempt,
              !schema2ColdRetainedOriginalSourceClosed,
              attempt.isCheckedClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRetainedSource(source)
        // The source latches its one-shot close before calling Darwin.close.
        // Keep Router admission live through its mandatory pre-close reproof;
        // a failed close stays terminal on that retained source object.
        try source.closeChecked()
        schema2ColdRetainedOriginalSourceClosed = true
    }

    func retainSchema2ColdOriginalContinuation(
        _ value: EraseSchema2ColdOriginalContinuationV1
    ) throws {
        if value.intent.phase == .emptyGenerationPrepared {
            try requireSchema2ColdPreparedTargetCurrentControls(
                intent: value.intent, preparation: value.preparation)
        } else {
            try requireSchema2ColdOriginalControls(
                intent: value.intent, preparation: value.preparation)
        }
        guard schema2ColdOriginalContinuation == nil,
              schema2ColdTargetContinuation == nil,
              let source = schema2ColdRetainedOriginalSource,
              schema2ColdPrivateSourceAttempt == nil,
              value.observed.intent == value.intent,
              value.observed.preparation == value.preparation,
              (value.intent.phase == .emptyGenerationPrepared &&
                value.phaseCut == nil ||
               value.intent.phase == .pointerSwitched &&
                value.phaseCut == nil ||
               value.intent.phase == .sessionActivated &&
                value.phaseCut != nil),
              value.generation.installedGenerationIDs.contains(
                value.intent.oldGenerationID),
              value.generation.installedGenerationIDs.contains(
                value.intent.newGenerationID),
              value.generation.manifest.generationID
                == value.intent.newGenerationID,
              value.generation.pointer.generationID
                == value.intent.newGenerationID.uuidString.lowercased(),
              value.generation.currentPointer.generationID
                == value.intent.oldGenerationID.uuidString.lowercased()
                    || value.generation.currentPointer.generationID
                        == value.intent.newGenerationID.uuidString.lowercased(),
              value.intent.phase != .emptyGenerationPrepared
                || value.generation.currentPointer.generationID
                    == value.intent.newGenerationID.uuidString.lowercased(),
              schema2ColdOriginalTokenCensus == value.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRetainedSource(source)
        schema2ColdOriginalContinuation = value
    }

    func requireSchema2ColdOriginalContinuation() throws
        -> (EraseSchema2ColdOriginalContinuationV1, EraseIntentStore,
            EraseSchema2ColdManifestOwnerV1,
            EraseSchema2ColdRetainedSourceV1,
            EraseSchema2ColdPhysicalExclusionV1,
            GenerationLeaseRegistryV1,
            GenerationTemporalActivityHandleV1) {
        try requireServiceAccess()
        guard let continuation = schema2ColdOriginalContinuation,
              !schema2ColdOriginalValidationComplete,
              let store = schema2ColdIntentStore,
              let manifest = schema2ColdManifestOwner,
              let source = schema2ColdRetainedOriginalSource,
              let exclusion = schema2ColdPhysicalExclusion,
              let registry, let activity = schema2ColdActivity,
              !schema2ColdIntentStoreClosed,
              !schema2ColdManifestOwnerClosed,
              !schema2ColdRetainedOriginalSourceClosed,
              !schema2ColdPhysicalExclusionClosed,
              schema2ColdOriginalTokenCensus == continuation.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if continuation.intent.phase == .emptyGenerationPrepared {
            try requireSchema2ColdPreparedTargetCurrentControls(
                intent: continuation.intent,
                preparation: continuation.preparation)
        } else {
            try requireSchema2ColdOriginalControls(
                intent: continuation.intent,
                preparation: continuation.preparation)
        }
        try requireSchema2ColdRetainedSource(source)
        return (continuation, store, manifest, source, exclusion,
            registry, activity)
    }

    fileprivate var hasSchema2ColdOriginalContinuation: Bool {
        schema2ColdOriginalContinuation != nil
            && !schema2ColdOriginalValidationComplete
            && !schema2ColdRetainedOriginalSourceClosed
    }

    /// The original private read is a distinct checked phase. Keep its exact
    /// physical source FD and typed original tree through the later target
    /// proof and prospective replay-roster publication. The private SQLite
    /// aliases have already drained, so this directory FD is not a reader
    /// lease or a live source ModelContext.
    func completeSchema2ColdOriginalValidation() throws {
        let (continuation, _, _, source, _, registry, _) =
            try requireSchema2ColdOriginalContinuation()
        guard let attempt = schema2ColdPrivateSourceAttempt,
              attempt.isCheckedClosed,
              schema2ColdValidatedOriginalTree == nil,
              !schema2ColdOriginalValidationComplete else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPredecessorGuards(registry: registry)
        let tree = try source.checkedOriginalTree()
        try requireSchema2ColdOriginalAuthority()
        schema2ColdValidatedOriginalTree =
            EraseSchema2ColdValidatedOriginalTreeV1(
                intent: continuation.intent,
                preparation: continuation.preparation,
                digest: tree.digest, nodes: tree.nodes)
        schema2ColdOriginalValidationComplete = true
    }

    /// A future deletion record may consume only these same validated bytes.
    /// The original root stays physically held until that record is durable;
    /// this getter grants no unlink or phase-mutation right by itself.
    func requireSchema2ColdValidatedOriginalTree()
        throws -> EraseSchema2ColdValidatedOriginalTreeV1 {
        try requireServiceAccess()
        guard schema2ColdOriginalValidationComplete,
              !schema2ColdRetainedOriginalSourceClosed,
              let source = schema2ColdRetainedOriginalSource,
              let witness = schema2ColdValidatedOriginalTree,
              let continuation = schema2ColdOriginalContinuation,
              witness.intent == continuation.intent,
              witness.preparation == continuation.preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRetainedSource(source)
        let current = try source.checkedOriginalTree()
        guard current.digest == witness.digest else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return witness
    }

    /// Bind durable original P records only after the actual cold EX/G owner
    /// and private old-source validation exist. This method has no effect
    /// callback and does not mint a target or auxiliary replay capability.
    func retainSchema2ColdOriginalRetiredSemantic(
        _ value: EraseSchema2ColdManifestOwnerV1
            .OriginalRetiredSemanticObservationV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws {
        try requireServiceAccess()
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdPreparedTargetCurrentControls(
            intent: intent, preparation: preparation)
        _ = try requireSchema2ColdValidatedOriginalTree()
        guard schema2ColdOriginalRetiredSemantic == nil,
              schema2ColdIntentStore === store,
              schema2ColdManifestOwner === manifest,
              let registry, let activity = schema2ColdActivity,
              let frozen = schema2ColdOriginalTokenCensus,
              try registry.observeEraseSchema2ColdRegistry(
                operation: self, activity: activity) == frozen else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdOriginalRetiredSemantic(
            value, intent: intent, preparation: preparation,
            store: store, operation: self)
        schema2ColdOriginalRetiredSemantic = value
    }

    func requireSchema2ColdOriginalRetiredSemantic(
        intent: EraseIntentV1,
        preparation: ErasePreparationV2
    ) throws -> EraseSchema2ColdManifestOwnerV1
        .OriginalRetiredSemanticObservationV1 {
        try requireServiceAccess()
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdPreparedTargetCurrentControls(
            intent: intent, preparation: preparation)
        _ = try requireSchema2ColdValidatedOriginalTree()
        guard let value = schema2ColdOriginalRetiredSemantic,
              let store = schema2ColdIntentStore,
              let manifest = schema2ColdManifestOwner,
              let registry, let activity = schema2ColdActivity,
              let frozen = schema2ColdOriginalTokenCensus,
              try registry.observeEraseSchema2ColdRegistry(
                operation: self, activity: activity) == frozen else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdOriginalRetiredSemantic(
            value, intent: intent, preparation: preparation,
            store: store, operation: self)
        return value
    }

    /// ManifestOwner has already retained every canonical migration leaf.
    /// Register the complete source map before it opens the first retired
    /// root FD, so a partial open failure remains on this operation.
    func retainSchema2ColdRetiredSources(
        _ value: [UUID: EraseSchema2ColdRetiredSourceV1]
    ) throws {
        try requireSchema2ColdOriginalAuthority()
        guard schema2ColdRetiredSources == nil,
              let store = schema2ColdIntentStore,
              let intent = try store.load(),
              let preparation = try store.loadPreparation(),
              intent.schemaVersion == 2,
              intent.phase == .pointerSwitched ||
                intent.phase == .sessionActivated,
              preparation.matches(intent),
              Set(value.keys).isSubset(of:
                  Set(intent.generationIDsToDelete).subtracting(
                      [intent.oldGenerationID])),
              value.allSatisfy({ element in
                  let (id, source) = element
                  return source.generationID == id && source.intent == intent
                    && source.preparation == preparation
                    && source.manifest.generationID == id
                    && source.manifest.storeSchemaRelease == .v53
              }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdRetiredSources = value
    }

    func requireSchema2ColdRetiredSource(
        _ source: EraseSchema2ColdRetiredSourceV1
    ) throws {
        try requireSchema2ColdOriginalAuthority()
        guard schema2ColdRetiredSources?[source.generationID] === source,
              !source.isCheckedClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireSchema2ColdRetiredSourceMap()
        throws -> [UUID: EraseSchema2ColdRetiredSourceV1] {
        try requireSchema2ColdOriginalAuthority()
        guard let sources = schema2ColdRetiredSources else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return sources
    }

    var hasSchema2ColdRetiredSourceMap: Bool {
        schema2ColdRetiredSources != nil
    }

    func retainSchema2ColdRetiredContinuation(
        _ value: EraseSchema2ColdRetiredContinuationV1
    ) throws {
        try requireSchema2ColdOriginalControls(
            intent: value.intent, preparation: value.preparation)
        guard schema2ColdRetiredContinuation == nil,
              schema2ColdRetiredSources == nil,
              value.observed.intent == value.intent,
              value.observed.preparation == value.preparation,
              value.registryTokens == schema2ColdOriginalTokenCensus,
              (value.intent.phase == .pointerSwitched &&
                value.phaseCut == nil ||
               value.intent.phase == .sessionActivated &&
                value.phaseCut != nil),
              value.generation.pointer.generationID
                == value.intent.newGenerationID.uuidString.lowercased() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdRetiredContinuation = value
    }

    func requireSchema2ColdRetiredContinuation() throws
        -> (EraseSchema2ColdRetiredContinuationV1, EraseIntentStore,
            EraseSchema2ColdManifestOwnerV1,
            EraseSchema2ColdPhysicalExclusionV1,
            GenerationLeaseRegistryV1,
            GenerationTemporalActivityHandleV1) {
        try requireServiceAccess()
        guard let continuation = schema2ColdRetiredContinuation,
              let store = schema2ColdIntentStore,
              let manifest = schema2ColdManifestOwner,
              let exclusion = schema2ColdPhysicalExclusion,
              let registry, let activity = schema2ColdActivity,
              !schema2ColdIntentStoreClosed,
              !schema2ColdManifestOwnerClosed,
              !schema2ColdPhysicalExclusionClosed,
              schema2ColdOriginalTokenCensus
                == continuation.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalControls(
            intent: continuation.intent,
            preparation: continuation.preparation)
        return (continuation, store, manifest, exclusion,
            registry, activity)
    }

    func requireSchema2ColdTargetAfterRetiredValidation() throws
        -> (EraseSchema2ColdRetiredContinuationV1,
            EraseSchema2ColdTargetSourceV1) {
        let (continuation, _, _, _, _, _) =
            try requireSchema2ColdRetiredContinuation()
        guard schema2ColdValidatedGenerationTrees != nil,
              let source = schema2ColdTargetSource,
              !schema2ColdTargetSourceClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdTargetSource(source)
        return (continuation, source)
    }

    func retainSchema2ColdRetiredPrivateAttempt(
        _ attempt: EraseSchema2ColdPrivateSourceAttemptV1,
        source: EraseSchema2ColdRetiredSourceV1
    ) throws {
        try requireSchema2ColdRetiredSource(source)
        guard schema2ColdRetiredPrivateAttempts[source.generationID] == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdRetiredPrivateAttempts[source.generationID] = attempt
    }

    func requireSchema2ColdRetiredPrivateAttempt(
        _ attempt: EraseSchema2ColdPrivateSourceAttemptV1,
        source: EraseSchema2ColdRetiredSourceV1
    ) throws {
        try requireSchema2ColdRetiredSource(source)
        guard schema2ColdRetiredPrivateAttempts[source.generationID]
                === attempt else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func schema2ColdRetiredPrivateAttempt(
        id: UUID
    ) -> EraseSchema2ColdPrivateSourceAttemptV1? {
        schema2ColdRetiredPrivateAttempts[id]
    }

    fileprivate var hasSchema2ColdRetiredValidationPending: Bool {
        schema2ColdRetiredContinuation != nil &&
            schema2ColdValidatedGenerationTrees == nil
    }

    /// Seal a complete first-snapshot partition only after every present
    /// frozen generation has passed the full private semantic validator and
    /// all of its private aliases/descriptors have checked-closed. This value
    /// is still not an unlink right; the same Manifest owner must durably
    /// publish its exact ordered roster before the first deletion effect.
    func completeSchema2ColdRetiredValidation(
        intent: EraseIntentV1
    ) throws {
        try requireServiceAccess()
        try requireSchema2ColdOriginalAuthority()
        guard schema2ColdValidatedGenerationTrees == nil,
              schema2ColdFirstAbsentGenerationIDs == nil,
              let sources = schema2ColdRetiredSources,
              let manifest = schema2ColdManifestOwner,
              let store = schema2ColdIntentStore,
              try store.load() == intent,
              intent.schemaVersion == 2,
              intent.phase == .pointerSwitched ||
                intent.phase == .sessionActivated else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        var present: [UUID: EraseSchema2ColdValidatedGenerationTreeV1] = [:]
        if let old = schema2ColdRetainedOriginalSource {
            guard schema2ColdOriginalValidationComplete,
                  let attempt = schema2ColdPrivateSourceAttempt,
                  attempt.isCheckedClosed,
                  !old.isCheckedClosed else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            _ = try requireSchema2ColdValidatedOriginalTree()
            present[old.generationID] = try .captureOld(
                source: old, attempt: attempt, operation: self)
        } else {
            try manifest.requireFirstOldSourceAbsence(
                intent: intent, operation: self)
        }
        for id in sources.keys.sorted(by: {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }) {
            guard let source = sources[id],
                  let attempt = schema2ColdRetiredPrivateAttempts[id],
                  attempt.isCheckedClosed,
                  !source.isCheckedClosed else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            present[id] = try .captureRetired(
                source: source, attempt: attempt, operation: self)
        }
        var absent = try manifest.requireFirstAbsentRetiredSourceIDs(
            intent: intent, operation: self)
        if schema2ColdRetainedOriginalSource == nil {
            absent.insert(intent.oldGenerationID)
        }
        guard Set(present.keys).isDisjoint(with: absent),
              Set(present.keys).union(absent)
                == Set(intent.generationIDsToDelete),
              Set(sources.keys)
                == Set(present.keys).subtracting(
                    [intent.oldGenerationID]) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdValidatedGenerationTrees = present
        schema2ColdFirstAbsentGenerationIDs = absent
    }

    func requireSchema2ColdValidatedGenerationTrees()
        throws -> (present: [UUID: EraseSchema2ColdValidatedGenerationTreeV1],
            absent: Set<UUID>) {
        try requireServiceAccess()
        try requireSchema2ColdOriginalAuthority()
        guard let present = schema2ColdValidatedGenerationTrees,
              let absent = schema2ColdFirstAbsentGenerationIDs,
              let store = schema2ColdIntentStore,
              let intent = try store.load(),
              Set(present.keys).isDisjoint(with: absent),
              Set(present.keys).union(absent)
                == Set(intent.generationIDsToDelete) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        for (id, tree) in present {
            guard tree.generationID == id else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            if id == intent.oldGenerationID {
                guard let source = schema2ColdRetainedOriginalSource,
                      let attempt = schema2ColdPrivateSourceAttempt,
                      attempt.isCheckedClosed,
                      try source.checkedOriginalTree().digest == tree.digest,
                      source.manifestDigest == tree.manifestDigest else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            } else {
                guard let source = schema2ColdRetiredSources?[id],
                      let attempt = schema2ColdRetiredPrivateAttempts[id],
                      attempt.isCheckedClosed,
                      try source.checkedOriginalTree().digest == tree.digest,
                      source.manifestDigest == tree.manifestDigest else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
        }
        return (present, absent)
    }

    /// A resumed original copy may now enter the already captured target
    /// phase. It uses the first immutable generation snapshot and the target
    /// owner opened before the original await; neither is re-created here.
    func requireSchema2ColdTargetAfterOriginal() throws
        -> (EraseSchema2ColdOriginalContinuationV1,
            EraseSchema2ColdTargetSourceV1) {
        try requireServiceAccess()
        guard schema2ColdOriginalValidationComplete,
              !schema2ColdRetainedOriginalSourceClosed,
              schema2ColdRetainedOriginalSource?.isCheckedClosed == false,
              schema2ColdValidatedOriginalTree != nil,
              let continuation = schema2ColdOriginalContinuation,
              let targetSource = schema2ColdTargetSource,
              targetSource.generationID == continuation.intent.newGenerationID,
              schema2ColdOriginalTokenCensus == continuation.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalControls(
            intent: continuation.intent,
            preparation: continuation.preparation)
        _ = try requireSchema2ColdValidatedOriginalTree()
        try requireSchema2ColdTargetSource(targetSource)
        return (continuation, targetSource)
    }

    func retainSchema2ColdTargetSource(
        _ value: EraseSchema2ColdTargetSourceV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdManifestOwner != nil,
              !schema2ColdManifestOwnerClosed,
              schema2ColdPhysicalExclusion != nil,
              !schema2ColdPhysicalExclusionClosed,
              schema2ColdTargetSource == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdTargetSource = value
    }

    func requireSchema2ColdTargetSource(
        _ expected: EraseSchema2ColdTargetSourceV1
    ) throws {
        try requireSchema2ColdManifestOwnerForTarget()
        guard schema2ColdTargetSource === expected,
              !schema2ColdTargetSourceClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private func requireSchema2ColdManifestOwnerForTarget() throws {
        guard let schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdManifestOwner(schema2ColdManifestOwner)
        guard let schema2ColdPhysicalExclusion,
              let schema2ColdSupportIdentity,
              !schema2ColdPhysicalExclusionClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try schema2ColdPhysicalExclusion.requireHeld(
            expectedDevice: schema2ColdSupportIdentity.device,
            expectedInode: schema2ColdSupportIdentity.inode)
    }

    func closeSchema2ColdTargetSourceChecked() throws {
        guard let schema2ColdTargetSource,
              !schema2ColdTargetSourceClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdTargetSource(schema2ColdTargetSource)
        // The source itself latches a one-shot ambiguous close. Router must
        // remain admissible during its required pre-close physical reproof.
        try schema2ColdTargetSource.closeChecked()
        schema2ColdTargetSourceClosed = true
    }

    func retainSchema2ColdTargetValidationAttempt(
        _ value: EraseSchema2ColdTargetValidationAttemptV1
    ) throws {
        guard let source = schema2ColdTargetSource else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdTargetSource(source)
        guard schema2ColdTargetValidationAttempt == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdTargetValidationAttempt = value
    }

    /// This P attempt is deliberately separate from the Q/R effect proof.
    /// The original source and target root were both captured before the
    /// original private read suspended; neither can be reconstructed here.
    func retainSchema2ColdPreparedTargetValidationAttempt(
        _ value: EraseSchema2ColdTargetValidationAttemptV1,
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        intent: EraseIntentV1
    ) throws {
        try requireServiceAccess()
        guard let continuation = schema2ColdOriginalContinuation,
              schema2ColdOriginalValidationComplete,
              continuation.intent == intent,
              intent.phase == .emptyGenerationPrepared,
              let source = schema2ColdTargetSource,
              source.generationID == intent.newGenerationID,
              schema2ColdPreparedTargetValidationAttempt == nil,
              schema2ColdTargetValidationAttempt == nil,
              !schema2ColdPreparedTargetPrivateValidated,
              let manifest = schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPreparedTargetCurrentControls(
            intent: intent, preparation: continuation.preparation)
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdTargetSource(source)
        try manifest.requireSchema2ColdTargetSnapshot(
            continuation.generation, intent: intent, operation: self)
        guard snapshot.currentPointer == continuation.generation.currentPointer,
              snapshot.pointer == continuation.generation.pointer,
              snapshot.manifest == continuation.generation.manifest,
              snapshot.installedGenerationIDs
                == continuation.generation.installedGenerationIDs,
              snapshot.retiredGenerationIDs
                == continuation.generation.retiredGenerationIDs else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdPreparedTargetValidationAttempt = value
    }

    func requireSchema2ColdPreparedTargetValidationAttempt(
        _ expected: EraseSchema2ColdTargetValidationAttemptV1
    ) throws {
        try requireServiceAccess()
        guard let continuation = schema2ColdOriginalContinuation,
              schema2ColdOriginalValidationComplete,
              continuation.intent.phase == .emptyGenerationPrepared,
              schema2ColdPreparedTargetValidationAttempt === expected,
              let source = schema2ColdTargetSource else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPreparedTargetCurrentControls(
            intent: continuation.intent,
            preparation: continuation.preparation)
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdTargetSource(source)
    }

    func bindSchema2ColdPreparedTargetPrivateValidated(
        source: EraseSchema2ColdTargetSourceV1,
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        attempt: EraseSchema2ColdTargetValidationAttemptV1
    ) throws {
        try requireSchema2ColdPreparedTargetValidationAttempt(attempt)
        guard let continuation = schema2ColdOriginalContinuation,
              !schema2ColdPreparedTargetPrivateValidated,
              attempt.isCheckedClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try attempt.requireCompletedPreparedTarget(source: source,
            snapshot: snapshot, intent: continuation.intent)
        schema2ColdPreparedTargetPrivateValidated = true
    }

    func retainSchema2ColdPreactivationContinuation(
        _ value: EraseSchema2ColdPreactivationContinuationV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdPreactivationContinuation == nil,
              schema2ColdTargetValidationAttempt == nil,
              schema2ColdPreactivationSnapshot == nil,
              schema2ColdTargetContinuation == nil,
              schema2ColdOriginalContinuation == nil
                || schema2ColdOriginalValidationComplete,
              value.intent.phase == .pointerSwitched,
              value.intent.schemaVersion == 2,
              let source = schema2ColdTargetSource,
              source.generationID == value.intent.newGenerationID,
              let manifest = schema2ColdManifestOwner,
              let registry,
              schema2ColdOriginalTokenCensus == value.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalControls(intent: value.intent,
            preparation: value.preparation)
        try requireSchema2ColdOriginalAuthority()
        try manifest.requireCapturedOperationsOwners(
            value.operationsNames, operation: self)
        try manifest.requireSchema2ColdTargetSnapshot(
            value.generation, intent: value.intent, operation: self)
        try requireSchema2ColdTargetSource(source)
        try requireSchema2ColdPredecessorGuards(registry: registry)
        schema2ColdPreactivationContinuation = value
    }

    func requireSchema2ColdPreactivationContinuation() throws
        -> (EraseSchema2ColdPreactivationContinuationV1,
            EraseIntentStore, EraseSchema2ColdManifestOwnerV1,
            EraseSchema2ColdTargetSourceV1,
            GenerationLeaseRegistryV1,
            GenerationTemporalActivityHandleV1) {
        try requireServiceAccess()
        guard let continuation = schema2ColdPreactivationContinuation,
              let store = schema2ColdIntentStore,
              !schema2ColdIntentStoreClosed,
              let manifest = schema2ColdManifestOwner,
              let source = schema2ColdTargetSource,
              !schema2ColdTargetSourceClosed,
              let registry, let activity = schema2ColdActivity,
              schema2ColdOriginalTokenCensus
                == continuation.registryTokens,
              source.generationID
                == continuation.intent.newGenerationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalControls(
            intent: continuation.intent,
            preparation: continuation.preparation)
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdTargetSource(source)
        try manifest.requireCapturedOperationsOwners(
            continuation.operationsNames, operation: self)
        if schema2ColdTargetPointerPublished {
            try manifest.requireSchema2ColdOwnPublishedSnapshot(
                continuation.generation, intent: continuation.intent,
                operation: self)
        } else {
            try manifest.requireSchema2ColdTargetSnapshot(
                continuation.generation, intent: continuation.intent,
                operation: self)
        }
        return (continuation, store, manifest, source,
            registry, activity)
    }

    fileprivate var hasSchema2ColdPreactivationContinuation: Bool {
        schema2ColdPreactivationContinuation != nil
            && schema2ColdTargetContinuation == nil
            && !schema2ColdPointerPhasePublished
    }

    /// Value-only phase selection for the same retained attempt. A retry
    /// after checked private-copy disposal must not allocate another copy;
    /// a retry after our pointer rename must not demand the initial old cut.
    var hasSchema2ColdPreactivationValidated: Bool {
        schema2ColdPreactivationSnapshot != nil
            && schema2ColdTargetValidationAttempt?.isCheckedClosed == true
            && !schema2ColdPointerPhasePublished
    }

    var hasSchema2ColdTargetPointerPublished: Bool {
        schema2ColdTargetPointerPublished
            && !schema2ColdPointerPhasePublished
    }

    func retainSchema2ColdActivatedEntryContinuation(
        _ value: EraseSchema2ColdActivatedEntryContinuationV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdActivatedEntryContinuation == nil,
              schema2ColdPreactivationContinuation == nil,
              schema2ColdTargetContinuation == nil,
              schema2ColdTargetValidationAttempt == nil,
              schema2ColdActivatedTargetAttempt == nil,
              let source = schema2ColdTargetSource,
              let manifest = schema2ColdManifestOwner,
              let registry, let activity = schema2ColdActivity,
              let store = schema2ColdIntentStore,
              value.intent.schemaVersion == 2,
              value.intent.phase == .sessionActivated,
              value.preparation.c05JobDrainV3 == nil,
              value.observed.intent == value.intent,
              value.observed.preparation == value.preparation,
              schema2ColdOriginalTokenCensus == value.registryTokens,
              source.generationID == value.intent.newGenerationID,
              value.generation.currentPointer
                == value.generation.pointer,
              case .published(let displaced, let displacedFact)
                = value.phaseCut,
              (displaced == nil) == (displacedFact == nil),
              value.observed.opaqueIntentNextPresent
                == (displaced != nil),
              try store.load() == value.intent,
              try store.loadPreparation() == value.preparation,
              try store.requireSchema2ColdPhaseCASCut(
                  expected: value.intent.advancing(to: .pointerSwitched),
                  replacement: value.intent, operation: self)
                == value.phaseCut,
              try registry.observeEraseSchema2ColdRegistry(
                  operation: self, activity: activity)
                == value.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalControls(
            intent: value.intent, preparation: value.preparation)
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdActivatedEntrySourceAuthority(
            value, store: store)
        try requireSchema2ColdTargetSource(source)
        try manifest.requireCapturedOperationsOwners(
            value.operationsNames, operation: self)
        try manifest.requireSchema2ColdTargetSnapshot(
            value.generation, intent: value.intent, operation: self)
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: value.intent, operation: self)
        try requireSchema2ColdPredecessorGuards(registry: registry)
        schema2ColdActivatedEntryContinuation = value
    }

    func requireSchema2ColdActivatedEntryContinuation() throws
        -> (EraseSchema2ColdActivatedEntryContinuationV1,
            EraseIntentStore, EraseSchema2ColdManifestOwnerV1,
            EraseSchema2ColdTargetSourceV1,
            GenerationLeaseRegistryV1,
            GenerationTemporalActivityHandleV1) {
        try requireSchema2ColdActivatedEntryContinuation(
            registryGAlreadyHeld: false)
    }

    private func requireSchema2ColdActivatedEntryContinuation(
        registryGAlreadyHeld: Bool
    ) throws -> (EraseSchema2ColdActivatedEntryContinuationV1,
        EraseIntentStore, EraseSchema2ColdManifestOwnerV1,
        EraseSchema2ColdTargetSourceV1,
        GenerationLeaseRegistryV1,
        GenerationTemporalActivityHandleV1) {
        try requireServiceAccess()
        guard let first = schema2ColdActivatedEntryContinuation,
              let store = schema2ColdIntentStore,
              !schema2ColdIntentStoreClosed,
              let manifest = schema2ColdManifestOwner,
              !schema2ColdManifestOwnerClosed,
              let source = schema2ColdTargetSource,
              !schema2ColdTargetSourceClosed,
              let registry, let activity = schema2ColdActivity,
              schema2ColdOriginalTokenCensus == first.registryTokens,
              try store.load() == first.intent,
              try store.loadPreparation() == first.preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalControls(
            intent: first.intent, preparation: first.preparation)
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdActivatedEntrySourceAuthority(
            first, store: store,
            registryGAlreadyHeld: registryGAlreadyHeld)
        try requireSchema2ColdTargetSource(source)
        try manifest.requireCapturedOperationsOwners(
            first.operationsNames, operation: self)
        try manifest.requireSchema2ColdTargetSnapshot(
            first.generation, intent: first.intent, operation: self)
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: first.intent, operation: self)
        let currentCut = try store.requireSchema2ColdPhaseCASCut(
            expected: first.intent.advancing(to: .pointerSwitched),
            replacement: first.intent, operation: self)
        guard currentCut == (schema2ColdActivatedEntryTempSettled
                ? .published(displacedBytes: nil, displacedFact: nil)
                : first.phaseCut) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if schema2ColdTargetReaderHandle == nil {
            if !registryGAlreadyHeld {
                guard try registry.observeEraseSchema2ColdRegistry(
                        operation: self, activity: activity)
                        == first.registryTokens else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            // With G already held, the Registry publisher reads and compares
            // these same prior tokens inside that lock before its first effect.
        } else if !registryGAlreadyHeld {
            try requireSchema2ColdTargetReaderTokenCensus(
                registry: registry)
        }
        return (first, store, manifest, source, registry, activity)
    }

    /// Exactly one first-R source authority is selected. An intact cut has
    /// complete private semantic witnesses for every present frozen ID; a
    /// rostered partial cut has only the first checked canonical R record.
    /// The latter is data until a retained executor later proves its global
    /// missing prefix under the same EX/G and actual target session.
    private func requireSchema2ColdActivatedEntrySourceAuthority(
        _ first: EraseSchema2ColdActivatedEntryContinuationV1,
        store: EraseIntentStore,
        registryGAlreadyHeld: Bool = false
    ) throws {
        if let roster = first.replayRoster {
            guard schema2ColdValidatedGenerationTrees == nil,
                  let observed = schema2ColdObservedReplayRoster,
                  observed.canonicalBytes == roster.canonicalBytes,
                  observed.canonicalSHA256 == roster.canonicalSHA256,
                  observed.recordFileFact == roster.recordFileFact,
                  schema2ColdRetainedOriginalSource == nil,
                  schema2ColdRetiredSources == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let cut = try store.requireSchema2ColdObservedRosterCut(
                intent: first.intent,
                preparation: first.preparation, operation: self,
                registryGAlreadyHeld: registryGAlreadyHeld)
            guard let leaf = cut.published,
                  cut.temporary == nil,
                  leaf.bytes == roster.canonicalBytes,
                  leaf.fact == roster.recordFileFact else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try store.requireSchema2ColdVerifiedObservedRosterPolicy(
                roster: roster, intent: first.intent,
                preparation: first.preparation, operation: self,
                registryGAlreadyHeld: registryGAlreadyHeld)
        } else {
            guard schema2ColdObservedReplayRoster == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            _ = try requireSchema2ColdValidatedGenerationTrees()
        }
    }

    fileprivate var hasSchema2ColdActivatedEntryContinuation: Bool {
        schema2ColdActivatedEntryContinuation != nil
    }

    var hasSchema2ColdActivatedEntryValidated: Bool {
        schema2ColdActivatedEntryValidated
            && schema2ColdTargetValidationAttempt?.isCheckedClosed == true
    }

    var hasSchema2ColdActivatedEntryTempSettled: Bool {
        schema2ColdActivatedEntryTempSettled
    }

    func bindSchema2ColdActivatedEntryValidated(
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        attempt: EraseSchema2ColdTargetValidationAttemptV1
    ) throws {
        let (first, _, manifest, source, registry, _) =
            try requireSchema2ColdActivatedEntryContinuation()
        guard !schema2ColdActivatedEntryValidated,
              schema2ColdTargetValidationAttempt === attempt,
              first.generation.pointer == snapshot.pointer,
              first.generation.currentPointer == snapshot.currentPointer,
              first.generation.manifest == snapshot.manifest,
              first.generation.installedGenerationIDs
                == snapshot.installedGenerationIDs,
              first.generation.retiredGenerationIDs
                == snapshot.retiredGenerationIDs else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try attempt.requireCompletedActivated(source: source,
            snapshot: snapshot, intent: first.intent)
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: first.intent, operation: self)
        try requireSchema2ColdPredecessorGuards(registry: registry)
        schema2ColdActivatedEntryValidated = true
    }

    func requireSchema2ColdActivatedEntryValidated(
        source: EraseSchema2ColdTargetSourceV1,
        intent: EraseIntentV1
    ) throws -> EraseSchema2ColdTargetSnapshotV1 {
        try requireSchema2ColdActivatedEntryValidated(
            source: source, intent: intent, registryGAlreadyHeld: false)
    }

    private func requireSchema2ColdActivatedEntryValidated(
        source: EraseSchema2ColdTargetSourceV1,
        intent: EraseIntentV1,
        registryGAlreadyHeld: Bool
    ) throws -> EraseSchema2ColdTargetSnapshotV1 {
        let (first, _, manifest, heldSource, _, _) =
            try requireSchema2ColdActivatedEntryContinuation(
                registryGAlreadyHeld: registryGAlreadyHeld)
        guard schema2ColdActivatedEntryValidated,
              heldSource === source,
              first.intent == intent,
              let attempt = schema2ColdTargetValidationAttempt else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try attempt.requireCompletedActivated(source: source,
            snapshot: first.generation, intent: intent)
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: intent, operation: self)
        return first.generation
    }

    /// The Registry may publish one target reader only after a complete
    /// operation-bound private target proof. P preactivation and first-R
    /// activated entry are separate closed stages; neither may borrow the
    /// other's intent bytes or validation attempt.
    func requireSchema2ColdTargetReaderAdmission(
        epoch: GenerationEpochV1,
        registry expectedRegistry: GenerationLeaseRegistryV1,
        activity expectedActivity: GenerationTemporalActivityHandleV1
    ) throws -> EraseSchema2ColdTargetReaderAdmissionV1 {
        try requireSchema2ColdTargetReaderAdmission(
            epoch: epoch, registry: expectedRegistry,
            activity: expectedActivity, registryGAlreadyHeld: false)
    }

    /// Registry publication calls this only while its actual G is held.
    /// The publisher itself checks the exact prior token bytes inside G;
    /// this operation reproof therefore omits only a recursive G read.
    func requireSchema2ColdTargetReaderAdmissionUnderHeldG(
        epoch: GenerationEpochV1,
        registry expectedRegistry: GenerationLeaseRegistryV1,
        activity expectedActivity: GenerationTemporalActivityHandleV1
    ) throws -> EraseSchema2ColdTargetReaderAdmissionV1 {
        try requireSchema2ColdTargetReaderAdmission(
            epoch: epoch, registry: expectedRegistry,
            activity: expectedActivity, registryGAlreadyHeld: true)
    }

    private func requireSchema2ColdTargetReaderAdmission(
        epoch: GenerationEpochV1,
        registry expectedRegistry: GenerationLeaseRegistryV1,
        activity expectedActivity: GenerationTemporalActivityHandleV1,
        registryGAlreadyHeld: Bool
    ) throws -> EraseSchema2ColdTargetReaderAdmissionV1 {
        try requireServiceAccess()
        try requireConstructedSchema2ColdRegistry(expectedRegistry)
        guard schema2ColdActivity === expectedActivity,
              let source = schema2ColdTargetSource,
              let manifest = schema2ColdManifestOwner,
              let prior = schema2ColdOriginalTokenCensus else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdPredecessorGuards(
            registry: expectedRegistry)
        try expectedRegistry.requireEraseSchema2ColdExcluded(
            operation: self, activity: expectedActivity)
        let value: EraseSchema2ColdTargetReaderAdmissionV1
        if schema2ColdPreactivationContinuation != nil {
            let (first, _, _, heldSource, _, _) =
                try requireSchema2ColdPreactivationContinuation()
            guard heldSource === source,
                  schema2ColdTargetPointerPublished,
                  schema2ColdFinalRetiredPublished else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let snapshot = try requireSchema2ColdPreactivationValidated(
                source: source, intent: first.intent)
            value = EraseSchema2ColdTargetReaderAdmissionV1(
                stage: .pointerPreactivation,
                intent: first.intent, preparation: first.preparation,
                targetSnapshot: snapshot, priorTokens: first.registryTokens)
        } else if schema2ColdActivatedEntryContinuation != nil {
            let (first, _, _, heldSource, _, _) =
                try requireSchema2ColdActivatedEntryContinuation(
                    registryGAlreadyHeld: registryGAlreadyHeld)
            guard heldSource === source else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let snapshot = try requireSchema2ColdActivatedEntryValidated(
                source: source, intent: first.intent,
                registryGAlreadyHeld: registryGAlreadyHeld)
            value = EraseSchema2ColdTargetReaderAdmissionV1(
                stage: first.replayRoster == nil
                    ? .activatedEntry : .activatedRosterReplay,
                intent: first.intent, preparation: first.preparation,
                targetSnapshot: snapshot, priorTokens: first.registryTokens)
        } else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard prior == value.priorTokens,
              value.targetSnapshot.pointer.generationID
                == epoch.generationID.uuidString.lowercased(),
              value.targetSnapshot.pointer.generationManifestSHA256
                == epoch.generationManifestSHA256 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: value.intent, operation: self)
        return value
    }

    var hasSchema2ColdFinalRetiredPublished: Bool {
        schema2ColdFinalRetiredPublished
            && !schema2ColdPointerPhasePublished
    }

    /// A checked private preactivation read is a prerequisite for any target
    /// pointer or lease effect. This records the first target/current cut;
    /// later callers reprove those held bytes instead of observing a new one.
    func bindSchema2ColdPreactivationValidated(
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        attempt: EraseSchema2ColdTargetValidationAttemptV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdPreactivationSnapshot == nil,
              schema2ColdTargetValidationAttempt === attempt,
              let source = schema2ColdTargetSource,
              let manifest = schema2ColdManifestOwner,
              let store = schema2ColdIntentStore,
              let intent = try store.load(),
              intent.schemaVersion == 2,
              intent.phase == .pointerSwitched,
              snapshot.pointer.generationID
                == intent.newGenerationID.uuidString.lowercased() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try attempt.requireCompletedPreactivation(
            source: source, snapshot: snapshot, intent: intent)
        try manifest.requireSchema2ColdTargetSnapshot(snapshot,
            intent: intent, operation: self)
        schema2ColdPreactivationSnapshot = snapshot
    }

    func requireSchema2ColdPreactivationValidated(
        source: EraseSchema2ColdTargetSourceV1,
        intent: EraseIntentV1
    ) throws -> EraseSchema2ColdTargetSnapshotV1 {
        try requireServiceAccess()
        guard let snapshot = schema2ColdPreactivationSnapshot,
              let attempt = schema2ColdTargetValidationAttempt,
              let manifest = schema2ColdManifestOwner,
              schema2ColdTargetSource === source,
              intent.phase == .pointerSwitched else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try attempt.requireCompletedPreactivation(
            source: source, snapshot: snapshot, intent: intent)
        if schema2ColdTargetPointerPublished {
            try manifest.requireSchema2ColdOwnPublishedSnapshot(
                snapshot, intent: intent, operation: self)
        } else {
            try manifest.requireSchema2ColdTargetSnapshot(snapshot,
                intent: intent, operation: self)
        }
        return snapshot
    }

    func publishSchema2ColdTargetPointer(
        intent: EraseIntentV1,
        source: EraseSchema2ColdTargetSourceV1
    ) throws {
        try requireServiceAccess()
        guard !schema2ColdTargetPointerPublished,
              let snapshot = schema2ColdPreactivationSnapshot,
              let manifest = schema2ColdManifestOwner,
              let registry, let activity = schema2ColdActivity,
              let tokens = schema2ColdOriginalTokenCensus,
              let store = schema2ColdIntentStore,
              try store.load() == intent,
              try manifest.observeAllowedCurrentCut(
                intent: intent, operation: self) == .old else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireSchema2ColdPreactivationValidated(
            source: source, intent: intent)
        try requireSchema2ColdOriginalAuthority()
        try registry.withEraseSchema2ColdUnchangedTokens(
            operation: self, activity: activity,
            expectedTokens: tokens) {
            try manifest.publishTargetPointerForSchema2Cold(
                intent: intent, snapshot: snapshot,
                operation: self)
        }
        schema2ColdTargetPointerPublished = true
        try manifest.requireSchema2ColdOwnPublishedSnapshot(
            snapshot, intent: intent, operation: self)
    }

    /// A new cold launch can start at the authenticated target-current cut.
    /// Its held first snapshot is the proof; no pointer writer or fresh
    /// postfailure baseline is credited to this operation.
    func retainSchema2ColdAlreadyPublishedTargetPointer(
        intent: EraseIntentV1,
        source: EraseSchema2ColdTargetSourceV1
    ) throws {
        try requireServiceAccess()
        guard !schema2ColdTargetPointerPublished,
              let snapshot = schema2ColdPreactivationSnapshot,
              snapshot.currentPointer == snapshot.pointer,
              let manifest = schema2ColdManifestOwner,
              let registry, let activity = schema2ColdActivity,
              let tokens = schema2ColdOriginalTokenCensus,
              let store = schema2ColdIntentStore,
              try store.load() == intent,
              try manifest.observeAllowedCurrentCut(
                intent: intent, operation: self) == .target else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireSchema2ColdPreactivationValidated(
            source: source, intent: intent)
        try registry.withEraseSchema2ColdUnchangedTokens(
            operation: self, activity: activity,
            expectedTokens: tokens) {
            try manifest.requireSchema2ColdTargetSnapshot(
                snapshot, intent: intent, operation: self)
        }
        schema2ColdTargetPointerPublished = true
    }

    func publishSchema2ColdFinalRetired(
        intent: EraseIntentV1,
        source: EraseSchema2ColdTargetSourceV1
    ) throws {
        try requireServiceAccess()
        guard !schema2ColdFinalRetiredPublished,
              let snapshot = schema2ColdPreactivationSnapshot,
              let manifest = schema2ColdManifestOwner,
              let registry, let activity = schema2ColdActivity,
              let tokens = schema2ColdOriginalTokenCensus,
              let store = schema2ColdIntentStore,
              try store.load() == intent else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireSchema2ColdPreactivationValidated(
            source: source, intent: intent)
        try manifest.requireSchema2ColdOwnPublishedSnapshot(
            snapshot, intent: intent, operation: self)
        try requireSchema2ColdOriginalAuthority()
        try registry.withEraseSchema2ColdUnchangedTokens(
            operation: self, activity: activity,
            expectedTokens: tokens) {
            try manifest.publishFinalRetiredForSchema2Cold(
                intent: intent, operation: self)
        }
        schema2ColdFinalRetiredPublished = true
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: intent, operation: self)
    }

    func retainSchema2ColdAlreadyFinalRetired(
        intent: EraseIntentV1,
        source: EraseSchema2ColdTargetSourceV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdTargetPointerPublished,
              !schema2ColdFinalRetiredPublished,
              let manifest = schema2ColdManifestOwner,
              let registry, let activity = schema2ColdActivity,
              let tokens = schema2ColdOriginalTokenCensus,
              let store = schema2ColdIntentStore,
              try store.load() == intent else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireSchema2ColdPreactivationValidated(
            source: source, intent: intent)
        try registry.withEraseSchema2ColdUnchangedTokens(
            operation: self, activity: activity,
            expectedTokens: tokens) {
            try manifest.requireSchema2ColdFinalPointerCut(
                intent: intent, operation: self)
        }
        schema2ColdFinalRetiredPublished = true
    }

    func retainSchema2ColdActivatedTargetAttempt(
        _ value: EraseSchema2ColdActivatedTargetAttemptV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdActivatedTargetAttempt == nil,
              schema2ColdTargetReaderAllocation == nil,
              schema2ColdActivatedTargetSession == nil,
              let source = schema2ColdTargetSource,
              let store = schema2ColdIntentStore,
              let intent = try store.load() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if schema2ColdPreactivationContinuation != nil {
            _ = try requireSchema2ColdPreactivationValidated(
                source: source, intent: intent)
        } else if schema2ColdActivatedEntryContinuation != nil {
            _ = try requireSchema2ColdActivatedEntryValidated(
                source: source, intent: intent)
        } else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdActivatedTargetAttempt = value
    }

    func requireSchema2ColdActivatedTargetAttempt(
        _ expected: EraseSchema2ColdActivatedTargetAttemptV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdActivatedTargetAttempt === expected,
              let source = schema2ColdTargetSource,
              let store = schema2ColdIntentStore,
              let intent = try store.load() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if schema2ColdTargetLiveOpenState == .inFlight {
            try requireSchema2ColdTargetLiveOpenInFlight(
                source: source, attempt: expected)
        } else if schema2ColdTargetLiveOpenState == .idle {
            if schema2ColdPreactivationContinuation != nil {
                _ = try requireSchema2ColdPreactivationValidated(
                    source: source, intent: intent)
            } else if schema2ColdActivatedEntryContinuation != nil {
                _ = try requireSchema2ColdActivatedEntryValidated(
                    source: source, intent: intent)
            } else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        } else {
            guard let manifest = schema2ColdManifestOwner else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try manifest.requireTargetSource(source, operation: self)
            try requireSchema2ColdOriginalAuthority()
        }
    }

    /// Latch the one owned SwiftData constructor after Factory has captured
    /// its exact preimage. No generic target-tree check is available again
    /// until the same attempt supplies a checked physical postimage.
    func beginSchema2ColdTargetLiveOpen(
        source: EraseSchema2ColdTargetSourceV1,
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        attempt: EraseSchema2ColdActivatedTargetAttemptV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdTargetLiveOpenState == .idle,
              schema2ColdActivatedTargetAttempt === attempt,
              schema2ColdTargetSource === source,
              let preactivation = schema2ColdTargetValidationAttempt,
              let manifest = schema2ColdManifestOwner,
              let store = schema2ColdIntentStore,
              let intent = try store.load(),
              intent.phase == .pointerSwitched else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try preactivation.requireCompletedPreactivation(
            source: source, snapshot: snapshot, intent: intent)
        guard schema2ColdTargetPointerPublished,
              schema2ColdFinalRetiredPublished,
              try requireSchema2ColdPreactivationValidated(
                source: source, intent: intent).pointer
                == snapshot.pointer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: intent, operation: self)
        try requireSchema2ColdOriginalAuthority()
        try manifest.beginTargetLiveOpen(source: source,
            operation: self)
        schema2ColdTargetLiveOpenState = .inFlight
    }

    /// First-R entry has its own authenticated activated-copy proof. It may
    /// open one real target session but can never replay the P pointer or
    /// intent CAS through the preactivation path.
    func beginSchema2ColdActivatedEntryLiveOpen(
        source: EraseSchema2ColdTargetSourceV1,
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        attempt: EraseSchema2ColdActivatedTargetAttemptV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdTargetLiveOpenState == .idle,
              schema2ColdActivatedTargetAttempt === attempt,
              schema2ColdTargetSource === source,
              let validated = schema2ColdTargetValidationAttempt,
              let manifest = schema2ColdManifestOwner,
              let store = schema2ColdIntentStore,
              let intent = try store.load(),
              intent.phase == .sessionActivated else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try validated.requireCompletedActivated(source: source,
            snapshot: snapshot, intent: intent)
        guard try requireSchema2ColdActivatedEntryValidated(
                source: source, intent: intent).pointer
                == snapshot.pointer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: intent, operation: self)
        try requireSchema2ColdOriginalAuthority()
        try manifest.beginTargetLiveOpen(source: source,
            operation: self)
        schema2ColdTargetLiveOpenState = .inFlight
    }

    func requireSchema2ColdTargetLiveOpenInFlight(
        source: EraseSchema2ColdTargetSourceV1,
        attempt: EraseSchema2ColdActivatedTargetAttemptV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdTargetLiveOpenState == .inFlight,
              schema2ColdActivatedTargetAttempt === attempt,
              schema2ColdTargetSource === source,
              let manifest = schema2ColdManifestOwner,
              let store = schema2ColdIntentStore,
              let intent = try store.load(),
              intent.phase == .pointerSwitched
                || intent.phase == .sessionActivated else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard (intent.phase == .pointerSwitched
                && schema2ColdPreactivationContinuation != nil)
                || (intent.phase == .sessionActivated
                    && schema2ColdActivatedEntryContinuation != nil) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalAuthority()
        try manifest.requireTargetLiveOpenControls(source: source,
            operation: self)
    }

    func finishSchema2ColdTargetLiveOpen(
        source: EraseSchema2ColdTargetSourceV1,
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        attempt: EraseSchema2ColdActivatedTargetAttemptV1,
        session: StoreGenerationSession,
        physical: EraseSchema2ColdTargetLiveOpenPhysicalV1
    ) throws {
        try requireSchema2ColdTargetLiveOpenInFlight(
            source: source, attempt: attempt)
        guard let preactivation = schema2ColdTargetValidationAttempt,
              let reader = schema2ColdTargetReaderHandle,
              let registry,
              session.generationID == source.generationID,
              session.readerLeaseToken == reader.token,
              snapshot.pointer.generationID
                == session.generationID.uuidString.lowercased() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try reader.requireExactRegistry(registry)
        try requireSchema2ColdTargetReaderTokenCensus(
            registry: registry)
        try physical.requireBoundToPreactivation(
            attempt: preactivation, snapshot: snapshot)
        try manifestForSchema2ColdTargetLiveOpen().finishTargetLiveOpen(
            source: source, physical: physical, operation: self)
        schema2ColdTargetLiveOpenState = .settled
    }

    func finishSchema2ColdActivatedEntryLiveOpen(
        source: EraseSchema2ColdTargetSourceV1,
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        attempt: EraseSchema2ColdActivatedTargetAttemptV1,
        session: StoreGenerationSession,
        physical: EraseSchema2ColdTargetLiveOpenPhysicalV1
    ) throws {
        try requireSchema2ColdTargetLiveOpenInFlight(
            source: source, attempt: attempt)
        guard let validated = schema2ColdTargetValidationAttempt,
              let reader = schema2ColdTargetReaderHandle,
              let registry,
              session.generationID == source.generationID,
              session.readerLeaseToken == reader.token,
              snapshot.pointer.generationID
                == session.generationID.uuidString.lowercased() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try reader.requireExactRegistry(registry)
        try requireSchema2ColdTargetReaderTokenCensus(
            registry: registry)
        try physical.requireBoundToActivated(
            attempt: validated, snapshot: snapshot)
        try manifestForSchema2ColdTargetLiveOpen().finishTargetLiveOpen(
            source: source, physical: physical, operation: self)
        schema2ColdTargetLiveOpenState = .settled
    }

    private func manifestForSchema2ColdTargetLiveOpen()
        throws -> EraseSchema2ColdManifestOwnerV1 {
        guard let manifest = schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return manifest
    }

    /// Registered before the first durable target reader token. The exact
    /// allocation remains pinned if publication or constructor completion is
    /// uncertain; a second allocation cannot replace it.
    func retainSchema2ColdTargetReaderAllocation(
        _ value: GenerationLeaseAllocationAttemptV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireServiceAccess()
        try requireConstructedSchema2ColdRegistry(expected)
        guard let activity = schema2ColdActivity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let admission = try requireSchema2ColdTargetReaderAdmission(
            epoch: value.generationEpoch, registry: expected,
            activity: activity)
        guard schema2ColdActivatedTargetAttempt != nil,
              schema2ColdTargetReaderAllocation == nil,
              schema2ColdTargetReaderAdmission == nil,
              schema2ColdTargetReaderHandle == nil,
              schema2ColdActivatedTargetSession == nil,
              value.matches(registry: expected),
              value.generationEpoch.generationID
                == UUID(uuidString: admission.targetSnapshot.pointer.generationID),
              value.generationEpoch.generationManifestSHA256
                == admission.targetSnapshot.pointer.generationManifestSHA256 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalAuthority()
        schema2ColdTargetReaderAdmission = admission
        schema2ColdTargetReaderAllocation = value
    }

    func requireSchema2ColdTargetReaderAllocation(
        _ expected: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1
    ) throws {
        try requireSchema2ColdTargetReaderAllocation(
            expected, registry: registry, registryGAlreadyHeld: false)
    }

    /// The Registry invokes this only inside its actual G. Its publisher
    /// compares the complete prior or prior-plus-own token census under that
    /// lock before accepting a record or effect; this reproof must not enter
    /// the Registry observer and recursively acquire G.
    func requireSchema2ColdTargetReaderAllocationUnderHeldG(
        _ expected: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1
    ) throws {
        try requireSchema2ColdTargetReaderAllocation(
            expected, registry: registry, registryGAlreadyHeld: true)
    }

    private func requireSchema2ColdTargetReaderAllocation(
        _ expected: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1,
        registryGAlreadyHeld: Bool
    ) throws {
        try requireConstructedSchema2ColdRegistry(registry)
        guard schema2ColdTargetReaderAllocation === expected,
              expected.matches(registry: registry),
              schema2ColdActivatedTargetAttempt != nil,
              let activity = schema2ColdActivity,
              let admission = schema2ColdTargetReaderAdmission,
              expected.generationEpoch.generationID
                == UUID(uuidString: admission.targetSnapshot.pointer.generationID),
              expected.generationEpoch.generationManifestSHA256
                == admission.targetSnapshot.pointer.generationManifestSHA256 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if schema2ColdTargetLiveOpenState == .inFlight {
            guard let source = schema2ColdTargetSource,
                  let attempt = schema2ColdActivatedTargetAttempt else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try requireSchema2ColdTargetLiveOpenInFlight(
                source: source, attempt: attempt)
        } else if let reader = schema2ColdTargetReaderHandle {
            // Publication has changed the Registry by precisely our retained
            // token. Under G, the Registry publisher checks the complete
            // prior-plus-own census directly; only the retained wrapper and
            // previously checked census can be inspected here.
            if registryGAlreadyHeld {
                guard let prior = schema2ColdOriginalTokenCensus,
                      let checked = schema2ColdTargetReaderTokenCensus,
                      checked.count == prior.count + 1,
                      checked.filter({ $0.leaseID == reader.token.leaseID })
                        == [reader.token],
                      prior.allSatisfy({ token in
                          checked.filter({ $0.leaseID == token.leaseID })
                            == [token]
                      }) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try reader.requireExactRegistry(registry)
            } else {
                try requireSchema2ColdTargetReaderTokenCensus(
                    registry: registry)
            }
        } else {
            let current = try requireSchema2ColdTargetReaderAdmission(
                epoch: expected.generationEpoch,
                registry: registry, activity: activity,
                registryGAlreadyHeld: registryGAlreadyHeld)
            guard current.stage == admission.stage,
                  current.intent == admission.intent,
                  current.preparation == admission.preparation,
                  current.priorTokens == admission.priorTokens,
                  current.targetSnapshot.currentPointer
                    == admission.targetSnapshot.currentPointer,
                  current.targetSnapshot.pointer
                    == admission.targetSnapshot.pointer,
                  current.targetSnapshot.manifest
                    == admission.targetSnapshot.manifest,
                  current.targetSnapshot.installedGenerationIDs
                    == admission.targetSnapshot.installedGenerationIDs,
                  current.targetSnapshot.retiredGenerationIDs
                    == admission.targetSnapshot.retiredGenerationIDs else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        try requireSchema2ColdOriginalAuthority()
    }

    /// The Registry calls this while the original G census still holds,
    /// before opening its durable target-reader publication record. It
    /// returns only the already retained Manifest owner; no fresh namespace
    /// observation or owner is constructed here.
    func requireSchema2ColdTargetReaderPublicationManifest(
        registry expected: GenerationLeaseRegistryV1,
        activity expectedActivity: GenerationTemporalActivityHandleV1
    ) throws -> EraseSchema2ColdManifestOwnerV1 {
        try requireServiceAccess()
        guard schema2ColdActivity === expectedActivity,
              schema2ColdTargetReaderHandle == nil,
              let manifest = schema2ColdManifestOwner,
              let allocation = schema2ColdTargetReaderAllocation,
              let admission = schema2ColdTargetReaderAdmission,
              allocation.matches(registry: expected) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Called inside the Registry's actual G. A full allocation reproof
        // would recurse through the R-entry token census and deadlock/refuse.
        // The Registry checks prior bytes under this same G before effect.
        try requireConstructedSchema2ColdRegistry(expected)
        try requireSchema2ColdOriginalAuthority()
        let current = try requireSchema2ColdTargetReaderAdmissionUnderHeldG(
            epoch: allocation.generationEpoch, registry: expected,
            activity: expectedActivity)
        guard current.stage == admission.stage,
              current.intent == admission.intent,
              current.preparation == admission.preparation,
              current.priorTokens == admission.priorTokens,
              current.targetSnapshot.pointer
                == admission.targetSnapshot.pointer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return manifest
    }

    func retainSchema2ColdTargetReaderHandle(
        _ value: GenerationLeaseHandleV1,
        allocation: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1
    ) throws {
        try requireServiceAccess()
        try requireConstructedSchema2ColdRegistry(registry)
        guard schema2ColdTargetReaderAllocation === allocation,
              allocation.matches(registry: registry),
              schema2ColdTargetReaderAdmission != nil,
              schema2ColdTargetReaderHandle == nil,
              schema2ColdTargetReaderTokenCensus == nil,
              allocation.allocatedHandle === value,
              value.token.role == .reader,
              value.token.epoch == allocation.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalAuthority()
        schema2ColdTargetReaderHandle = value
        try requireSchema2ColdTargetReaderTokenCensus(
            registry: registry)
    }

    /// The exact cold insertion is the first frozen old census plus only
    /// this operation's retained target reader token. Reobserve under G on
    /// every later use; an equal count alone never admits a foreign token.
    func requireSchema2ColdTargetReaderTokenCensus(
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedSchema2ColdRegistry(expected)
        guard let prior = schema2ColdOriginalTokenCensus,
              let handle = schema2ColdTargetReaderHandle,
              let activity = schema2ColdActivity,
              handle.token.role == .reader,
              !prior.contains(where: {
                  $0.leaseID == handle.token.leaseID
              }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let observed = try expected.observeEraseSchema2ColdRegistry(
            operation: self, activity: activity)
        guard observed.count == prior.count + 1,
              prior.allSatisfy({ token in
                  observed.filter({ $0.leaseID == token.leaseID })
                    == [token]
              }),
              observed.filter({
                  $0.leaseID == handle.token.leaseID
              }) == [handle.token],
              schema2ColdTargetReaderTokenCensus == nil
                || schema2ColdTargetReaderTokenCensus == observed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdTargetReaderTokenCensus = observed
    }

    func retainSchema2ColdActivatedTargetSession(
        _ session: StoreGenerationSession,
        attempt: EraseSchema2ColdActivatedTargetAttemptV1
    ) throws {
        try requireSchema2ColdActivatedTargetAttempt(attempt)
        guard schema2ColdActivatedTargetSession == nil,
              let allocation = schema2ColdTargetReaderAllocation,
              let handle = schema2ColdTargetReaderHandle,
              session.generationID == allocation.generationEpoch.generationID,
              session.generationEpoch == allocation.generationEpoch,
              session.readerLeaseToken == handle.token,
              session.generationRootURL.standardizedFileURL
                == factory.installedGenerationURL(
                    id: session.generationID).standardizedFileURL else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdActivatedTargetSession = session
    }

    func requireSchema2ColdActivatedTargetSession()
        throws -> StoreGenerationSession {
        try requireServiceAccess()
        guard let session = schema2ColdActivatedTargetSession,
              let allocation = schema2ColdTargetReaderAllocation,
              let handle = schema2ColdTargetReaderHandle,
              let registry,
              session.generationID == allocation.generationEpoch.generationID,
              session.generationEpoch == allocation.generationEpoch,
              session.readerLeaseToken == handle.token else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdTargetReaderAllocation(allocation,
            registry: registry)
        return session
    }

    /// The borrowed Store may enter its canonical CAS only after the same
    /// operation has a real target container, the exact target reader under
    /// G, and both final pointer controls. A thrown CAS remains on this
    /// retained operation; it cannot become a fresh startup baseline.
    func withSchema2ColdPointerPhaseMutation(
        expected: EraseIntentV1,
        replacement: EraseIntentV1,
        store: EraseIntentStore,
        _ body: () throws -> Void
    ) throws {
        try requireServiceAccess()
        try requireSchema2ColdIntentStore(store)
        guard !schema2ColdPointerPhasePublished,
              expected.schemaVersion == 2,
              expected.phase == .pointerSwitched,
              replacement == expected.advancing(to: .sessionActivated),
              let registry, let activity = schema2ColdActivity,
              let manifest = schema2ColdManifestOwner,
              let source = schema2ColdTargetSource,
              let snapshot = schema2ColdPreactivationSnapshot,
              let attempt = schema2ColdActivatedTargetAttempt,
              let prior = schema2ColdTargetReaderTokenCensus,
              let heldSession = schema2ColdActivatedTargetSession else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let firstCut = try store.requireSchema2ColdPhaseCASCut(
            expected: expected, replacement: replacement,
            operation: self)
        let verified = try attempt.requireCompletedLiveOpen(
            source: source, snapshot: snapshot, operation: self)
        guard verified === heldSession,
              try requireSchema2ColdActivatedTargetSession() === heldSession else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: expected, operation: self)
        try requireSchema2ColdTargetReaderTokenCensus(registry: registry)
        try registry.withEraseSchema2ColdUnchangedTokens(
            operation: self, activity: activity,
            expectedTokens: prior) {
            guard try store.requireSchema2ColdPhaseCASCut(
                    expected: expected, replacement: replacement,
                    operation: self) == firstCut else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try manifest.requireSchema2ColdFinalPointerCut(
                intent: expected, operation: self)
            try body()
            guard try store.load() == replacement else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard try store.requireSchema2ColdPhaseCASCut(
                    expected: expected, replacement: replacement,
                    operation: self) == .published(
                        displacedBytes: nil, displacedFact: nil) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try manifest.requireSchema2ColdFinalPointerCut(
                intent: replacement, operation: self)
        }
        // The exact post-CAS bytes were proved while G was held. This is a
        // one-way receipt, never an invitation to retry the canonical write.
        schema2ColdPointerPhasePublished = true
        schema2ColdPublishedIntent = replacement
    }

    func requireSchema2ColdPointerPhasePublished(
        expected: EraseIntentV1,
        store: EraseIntentStore
    ) throws -> StoreGenerationSession {
        try requireServiceAccess()
        try requireSchema2ColdIntentStore(store)
        guard schema2ColdPointerPhasePublished,
              schema2ColdPublishedIntent == expected,
              expected.phase == .sessionActivated,
              try store.load() == expected,
              let manifest = schema2ColdManifestOwner,
              let registry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: expected, operation: self)
        try requireSchema2ColdTargetReaderTokenCensus(registry: registry)
        return try requireSchema2ColdActivatedTargetSession()
    }

    /// A fresh authenticated R entry never performs P→R again. Only the
    /// exact displaced P temporary from its first held cut may be removed,
    /// after the target's real reader/session and physical open are proved.
    func withSchema2ColdActivatedEntryTempCleanup(
        pending: EraseIntentV1,
        published: EraseIntentV1,
        store: EraseIntentStore,
        _ body: () throws -> Void
    ) throws {
        try requireServiceAccess()
        try requireSchema2ColdIntentStore(store)
        let (first, heldStore, manifest, source, registry, activity) =
            try requireSchema2ColdActivatedEntryContinuation()
        guard heldStore === store,
              !schema2ColdActivatedEntryTempSettled,
              pending.phase == .pointerSwitched,
              published == pending.advancing(to: .sessionActivated),
              first.intent == published,
              let attempt = schema2ColdActivatedTargetAttempt,
              let session = schema2ColdActivatedTargetSession,
              let prior = schema2ColdTargetReaderTokenCensus,
              try store.requireSchema2ColdPhaseCASCut(
                  expected: pending, replacement: published,
                  operation: self) == first.phaseCut,
              try attempt.requireCompletedLiveOpen(
                  source: source, snapshot: first.generation,
                  operation: self) === session,
              try requireSchema2ColdActivatedTargetSession() === session else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: published, operation: self)
        try requireSchema2ColdTargetReaderTokenCensus(registry: registry)
        try registry.withEraseSchema2ColdUnchangedTokens(
            operation: self, activity: activity,
            expectedTokens: prior) {
            guard try store.requireSchema2ColdPhaseCASCut(
                    expected: pending, replacement: published,
                    operation: self) == first.phaseCut else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try manifest.requireSchema2ColdFinalPointerCut(
                intent: published, operation: self)
            try body()
            guard try store.load() == published,
                  try store.requireSchema2ColdPhaseCASCut(
                      expected: pending, replacement: published,
                      operation: self) == .published(
                          displacedBytes: nil, displacedFact: nil) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try manifest.requireSchema2ColdFinalPointerCut(
                intent: published, operation: self)
        }
        schema2ColdActivatedEntryTempSettled = true
    }

    func requireSchema2ColdActivatedEntryTempSettled(
        store: EraseIntentStore
    ) throws -> StoreGenerationSession {
        let (first, heldStore, manifest, source, registry, _) =
            try requireSchema2ColdActivatedEntryContinuation()
        guard heldStore === store,
              schema2ColdActivatedEntryTempSettled,
              try store.load() == first.intent,
              let attempt = schema2ColdActivatedTargetAttempt,
              let session = schema2ColdActivatedTargetSession,
              try attempt.requireCompletedLiveOpen(
                  source: source, snapshot: first.generation,
                  operation: self) === session else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: first.intent, operation: self)
        try requireSchema2ColdTargetReaderTokenCensus(registry: registry)
        return try requireSchema2ColdActivatedTargetSession()
    }

    /// The durable P→R CAS is an intermediate cold cut, not cleanup or fresh
    /// publication. Resume on this exact operation with its original frozen
    /// preparation, real target session and reader; no P-only constructor is
    /// re-entered and no post-CAS control becomes a new baseline.
    func requireSchema2ColdActivatedForwardContinuation() throws
        -> (publishedIntent: EraseIntentV1,
            store: EraseIntentStore,
            session: StoreGenerationSession,
            preparation: ErasePreparationV2,
            manifest: EraseSchema2ColdManifestOwnerV1,
            source: EraseSchema2ColdTargetSourceV1,
            registry: GenerationLeaseRegistryV1,
            activity: GenerationTemporalActivityHandleV1) {
        try requireServiceAccess()
        guard let intent = schema2ColdPublishedIntent,
              let first = schema2ColdPreactivationContinuation,
              let store = schema2ColdIntentStore,
              let manifest = schema2ColdManifestOwner,
              let source = schema2ColdTargetSource,
              let registry, let activity = schema2ColdActivity,
              !schema2ColdManifestOwnerClosed,
              !schema2ColdTargetSourceClosed,
              !schema2ColdIntentStoreClosed,
              intent == first.intent.advancing(to: .sessionActivated),
              try store.loadPreparation() == first.preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalAuthority()
        try requireSchema2ColdTargetSource(source)
        try manifest.requireCapturedOperationsOwners(
            first.operationsNames, operation: self)
        let session = try requireSchema2ColdPointerPhasePublished(
            expected: intent, store: store)
        return (intent, store, session, first.preparation,
            manifest, source, registry, activity)
    }

    /// Publication admission is deliberately separate from roster bytes:
    /// the same operation must hold an actual R target session/reader and a
    /// complete semantically validated first-snapshot partition. Only the
    /// borrowed Store can then own the Erase record's checked descriptor.
    func requireSchema2ColdRosterAdmission(
        intent: EraseIntentV1, store: EraseIntentStore
    ) throws {
        try requireServiceAccess()
        try requireSchema2ColdIntentStore(store)
        guard !schema2ColdRosterPublished,
              intent.schemaVersion == 2,
              intent.phase == .sessionActivated,
              let preparation = try store.loadPreparation(),
              preparation.matches(intent),
              try store.load() == intent,
              let manifest = schema2ColdManifestOwner,
              let registry, let activity = schema2ColdActivity,
              let exclusion = schema2ColdPhysicalExclusion,
              let identity = schema2ColdSupportIdentity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalAuthority()
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try registry.requireEraseSchema2ColdExcluded(
            operation: self, activity: activity)
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: intent, operation: self)
        _ = try requireSchema2ColdValidatedGenerationTrees()
        if schema2ColdPointerPhasePublished {
            _ = try requireSchema2ColdPointerPhasePublished(
                expected: intent, store: store)
        } else {
            let (first, held, _, _, _, _) =
                try requireSchema2ColdActivatedEntryContinuation()
            guard held === store, first.intent == intent,
                  schema2ColdActivatedEntryTempSettled else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            _ = try requireSchema2ColdActivatedEntryTempSettled(
                store: store)
        }
        try requireSchema2ColdTargetReaderTokenCensus(
            registry: registry)
    }

    /// A fresh R cut may already carry a prospective roster. Observe that
    /// reserved namespace only after the genuine retained Support EX and
    /// Registry G exist, before any original-generation semantic open. This
    /// grants no authority to decode a record or delete a survivor.
    func requireSchema2ColdRosterObservationOwner(
        store: EraseIntentStore,
        registryGAlreadyHeld: Bool = false
    ) throws {
        try requireServiceAccess()
        try requireSchema2ColdIntentStore(store)
        guard let manifest = schema2ColdManifestOwner,
              let exclusion = schema2ColdPhysicalExclusion,
              let identity = schema2ColdSupportIdentity,
              let registry, let activity = schema2ColdActivity,
              let intent = try store.load(),
              let preparation = try store.loadPreparation(),
              intent.schemaVersion == 2,
              intent.phase == .sessionActivated,
              preparation.matches(intent) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdOriginalAuthority()
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try registry.requireEraseSchema2ColdExcluded(
            operation: self, activity: activity)
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: intent, operation: self)
        // The under-G variant is exclusively the first publication path.
        // Once a target handle exists, only the ordinary fresh census proof
        // can revalidate it; a second publication is never admitted.
        guard !registryGAlreadyHeld ||
                schema2ColdTargetReaderHandle == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if schema2ColdTargetReaderHandle == nil {
            let prior = try requireSchema2ColdOriginalTokenCensus(
                registry: registry)
            if !registryGAlreadyHeld {
                guard try registry.observeEraseSchema2ColdRegistry(
                    operation: self, activity: activity) == prior else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
        } else {
            try requireSchema2ColdTargetReaderTokenCensus(
                registry: registry)
        }
    }

    /// Manifest seals the complete first-snapshot partition before Store can
    /// create the roster temporary. The same reference and canonical bytes
    /// must authorize every later checked write/readback on this operation.
    /// Decoder output is data until a concrete retained executor proves the
    /// complete roster prefix. Bind its original checked leaf bytes and fact
    /// before that first survivor FD is opened.
    func retainSchema2ColdDecodedRosterForReplay(
        _ roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore
    ) throws {
        try requireSchema2ColdRosterObservationOwner(store: store)
        guard schema2ColdObservedReplayRoster == nil,
              schema2ColdRosterPublicationSeal == nil,
              schema2ColdPublishedRoster == nil,
              schema2ColdDeletionExecutor == nil,
              schema2ColdRetainedOriginalSource == nil,
              schema2ColdRetiredSources == nil,
              let intent = try store.load(),
              let preparation = try store.loadPreparation() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let cut = try store.requireSchema2ColdObservedRosterCut(
            intent: intent, preparation: preparation,
            operation: self)
        guard let leaf = cut.published,
              cut.temporary == nil,
              leaf.bytes == roster.canonicalBytes,
              leaf.fact == roster.recordFileFact else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try store.requireSchema2ColdVerifiedObservedRosterPolicy(
            roster: roster, intent: intent,
            preparation: preparation, operation: self)
        schema2ColdObservedReplayRoster = roster
    }

    func requireSchema2ColdObservedReplayRoster(
        canonicalBytes: Data,
        recordFact: EraseColdControlLeafFactV1,
        store: EraseIntentStore
    ) throws -> EraseSchema2ColdDeletionRosterV1 {
        guard schema2ColdIntentStore === store,
              let roster = schema2ColdObservedReplayRoster,
              roster.canonicalBytes == canonicalBytes,
              roster.recordFileFact == recordFact,
              roster.canonicalSHA256 ==
                StoreMigrationCanonicalJSONV1.sha256(canonicalBytes) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return roster
    }

    func requireSchema2ColdReplayExecutorAdmission(
        executor: EraseSchema2ColdCheckedDeletionExecutorV1,
        roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore
    ) throws {
        try requireSchema2ColdRosterObservationOwner(store: store)
        guard schema2ColdDeletionExecutor === executor,
              let observed = schema2ColdObservedReplayRoster,
              observed.canonicalBytes == roster.canonicalBytes,
              observed.canonicalSHA256 == roster.canonicalSHA256,
              observed.recordFileFact == roster.recordFileFact,
              schema2ColdRetainedOriginalSource == nil,
              schema2ColdRetiredSources == nil,
              let intent = try store.load(),
              let preparation = try store.loadPreparation() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let cut = try store.requireSchema2ColdObservedRosterCut(
            intent: intent, preparation: preparation,
            operation: self)
        guard let leaf = cut.published,
              cut.temporary == nil,
              leaf.bytes == roster.canonicalBytes,
              leaf.fact == roster.recordFileFact else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// Manifest calls this after full checked survivor-prefix admission and
    /// one-way projection of its held generations parent/name set.
    func bindSchema2ColdObservedRosterAfterReplay(
        _ roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore
    ) throws {
        guard let executor = schema2ColdDeletionExecutor else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdReplayExecutorAdmission(
            executor: executor, roster: roster, store: store)
        guard !schema2ColdRosterPublished,
              schema2ColdPublishedRoster == nil,
              let manifest = schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requirePublishedSchema2ColdDeletionRoster(
            roster, store: store, operation: self)
        schema2ColdPublishedRoster = roster
        schema2ColdRosterPublished = true
    }

    func retainSchema2ColdRosterPublicationSeal(
        _ seal: EraseSchema2ColdDeletionRosterPublicationSealV1,
        intent: EraseIntentV1,
        store: EraseIntentStore
    ) throws {
        try requireSchema2ColdRosterAdmission(intent: intent,
            store: store)
        guard schema2ColdRosterPublicationSeal == nil,
              let preparation = try store.loadPreparation(),
              let manifest = schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try seal.requireBound(manifest: manifest, intent: intent,
            preparation: preparation, operation: self)
        schema2ColdRosterPublicationSeal = seal
        schema2ColdRosterFirstIntent = intent
        schema2ColdRosterFirstPreparation = preparation
    }

    func requireSchema2ColdRosterPublicationSeal(
        _ seal: EraseSchema2ColdDeletionRosterPublicationSealV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdRosterPublicationSeal === seal,
              let intent = schema2ColdRosterFirstIntent,
              let preparation = schema2ColdRosterFirstPreparation,
              let manifest = schema2ColdManifestOwner,
              let store = schema2ColdIntentStore,
              !schema2ColdRosterPublished else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRosterEffectOwner(store: store)
        try seal.requireBound(manifest: manifest, intent: intent,
            preparation: preparation, operation: self)
    }

    /// Store calls this after its temporary has complete checked bytes and
    /// policy, immediately before the no-replace rename. The same retained
    /// first generation trees and absence cut must still match the seal.
    func requireSchema2ColdRosterSourceFactsBeforeRename(
        seal: EraseSchema2ColdDeletionRosterPublicationSealV1,
        store: EraseIntentStore
    ) throws {
        try requireSchema2ColdIntentStore(store)
        try requireSchema2ColdRosterPublicationSeal(seal)
    }

    /// A captured roster temporary is not publication authority. Before and
    /// after its one checked unlink, the same complete validated source
    /// trees, R controls, real target session, EX and G must still match the
    /// operation-sealed canonical record. No Store.load() or Erase-root
    /// baseline is taken inside the effect interval.
    func requireSchema2ColdRosterSourceFactsBeforeTempRemoval(
        seal: EraseSchema2ColdDeletionRosterPublicationSealV1,
        store: EraseIntentStore
    ) throws {
        try requireSchema2ColdIntentStore(store)
        guard schema2ColdRosterPublicationSeal === seal,
              let manifest = schema2ColdManifestOwner,
              let intent = schema2ColdRosterFirstIntent,
              let preparation = schema2ColdRosterFirstPreparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRosterEffectOwner(store: store)
        try seal.requireBound(manifest: manifest, intent: intent,
            preparation: preparation, operation: self)
    }

    /// Once Store has checked the exact canonical file and Manifest retains
    /// it, the operation records that one-way fact before any generation
    /// unlink. A merely constructed seal is never deletion authority.
    func bindSchema2ColdPublishedRoster(
        _ roster: EraseSchema2ColdDeletionRosterV1,
        seal: EraseSchema2ColdDeletionRosterPublicationSealV1,
        store: EraseIntentStore,
        recordFact: EraseColdControlLeafFactV1
    ) throws {
        try requireSchema2ColdRosterPublicationSeal(seal)
        guard !schema2ColdRosterPublished,
              schema2ColdPublishedRoster == nil,
              roster.canonicalBytes == seal.canonicalBytes,
              roster.canonicalSHA256 == seal.canonicalSHA256,
              roster.recordFileFact == recordFact,
              let manifest = schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requirePublishedSchema2ColdDeletionRoster(
            roster, store: store, operation: self)
        schema2ColdPublishedRoster = roster
        schema2ColdRosterPublished = true
    }

    /// Narrow EX/G/session proof used by Store while it observes its own
    /// published Erase leaf. It never calls Manifest's roster reproof, so the
    /// Manifest→Store→Router chain cannot recurse.
    func requireSchema2ColdPublishedRosterControlOwner(
        store: EraseIntentStore
    ) throws {
        try requireServiceAccess()
        try requireSchema2ColdIntentStore(store)
        try requireSchema2ColdOriginalAuthority()
        guard let exclusion = schema2ColdPhysicalExclusion,
              let identity = schema2ColdSupportIdentity,
              let registry, let activity = schema2ColdActivity,
              (schema2ColdRosterPublicationSeal != nil
                || schema2ColdObservedReplayRoster != nil),
              schema2ColdActivatedTargetSession != nil,
              schema2ColdTargetReaderHandle != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try registry.requireEraseSchema2ColdExcluded(
            operation: self, activity: activity)
        try requireSchema2ColdTargetReaderTokenCensus(
            registry: registry)
    }

    func requireSchema2ColdRosterStepOwner(
        roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore
    ) throws {
        guard schema2ColdRosterPublished,
              let held = schema2ColdPublishedRoster,
              held.canonicalSHA256 == roster.canonicalSHA256,
              held.canonicalBytes == roster.canonicalBytes,
              held.recordFileFact == roster.recordFileFact,
              let manifest = schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPublishedRosterControlOwner(store: store)
        try manifest.requirePublishedSchema2ColdDeletionRoster(
            roster, store: store, operation: self)
    }

    var hasSchema2ColdPublishedRoster: Bool {
        schema2ColdRosterPublished
    }

    func requireSchema2ColdPublishedRoster(
        store: EraseIntentStore
    ) throws -> EraseSchema2ColdDeletionRosterV1 {
        guard let roster = schema2ColdPublishedRoster else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRosterStepOwner(
            roster: roster, store: store)
        return roster
    }

    /// Retain the exact no-create notification owner before its first root or
    /// leaf descriptor. The published roster and real target session remain
    /// the prerequisite for every later notification effect.
    func retainSchema2ColdNotificationControl(
        _ control: any Schema2ColdNotificationEraseControlV1,
        source: EraseSchema2ColdNotificationSourceV1,
        store: EraseIntentStore
    ) throws {
        guard schema2ColdNotificationSource == nil,
              schema2ColdNotificationControl == nil,
              schema2ColdNotificationDrainReceipt == nil,
              let manifest = schema2ColdManifestOwner,
              source.eraseID == (try store.load()?.eraseID) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try requireSchema2ColdPublishedRoster(store: store)
        try manifest.requireSchema2ColdNotificationSource(
            source, operation: self)
        schema2ColdNotificationSource = source
        schema2ColdNotificationControl = control
    }

    var hasSchema2ColdNotificationControl: Bool {
        schema2ColdNotificationControl != nil
    }

    var hasSchema2ColdNotificationDrainReceipt: Bool {
        schema2ColdNotificationDrainReceipt != nil
    }

    func requireSchema2ColdNotificationControl(
        store: EraseIntentStore
    ) throws -> (any Schema2ColdNotificationEraseControlV1,
                 EraseSchema2ColdNotificationSourceV1) {
        guard let source = schema2ColdNotificationSource,
              let control = schema2ColdNotificationControl,
              let manifest = schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPublishedRosterControlOwner(
            store: store)
        try manifest.requireSchema2ColdNotificationSource(
            source, operation: self)
        return (control, source)
    }

    /// This narrower proof is safe during the Manifest's one-way notification
    /// mutation. Generic roster/notification root reproof would demand stale
    /// pre-effect directory metadata, so the Manifest checks its own exact
    /// stage projection and the Router retains the same source and OS owner.
    func requireSchema2ColdNotificationMutationOwner(
        source: EraseSchema2ColdNotificationSourceV1,
        stage: EraseSchema2ColdNotificationMutationStageV1
    ) throws {
        guard schema2ColdNotificationSource === source,
              let control = schema2ColdNotificationControl,
              let store = schema2ColdIntentStore,
              let manifest = schema2ColdManifestOwner,
              let roster = schema2ColdPublishedRoster,
              schema2ColdRosterPublished,
              roster.record.eraseID == source.eraseID.uuidString.lowercased(),
              let intent = try store.load(),
              intent.eraseID == source.eraseID,
              intent.phase == .sessionActivated else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPublishedRosterControlOwner(store: store)
        try manifest.requireSchema2ColdNotificationSource(
            source, operation: self)
        if stage == .createRoot {
            guard source.rootIdentity == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        } else if stage == .settleCreatedRoot {
            guard source.rootIdentity != nil,
                  source.hasAuthenticatedCreationRecord,
                  source.names.isEmpty,
                  try source.requireCurrentRootIdentity()
                    == control.notificationRootIdentity else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        } else {
            guard try source.requireCurrentRootIdentity()
                    == control.notificationRootIdentity
                else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        if stage == .publishDrainReceipt || stage == .removeMapping
            || stage == .removeControl {
            try control.requireSchema2ColdOSAbsence(stage: stage)
        }
    }

    func retainSchema2ColdNotificationDrainReceipt(
        _ receipt: EraseSchema2ColdNotificationDrainReceiptV1,
        control: any Schema2ColdNotificationEraseControlV1,
        source: EraseSchema2ColdNotificationSourceV1,
        store: EraseIntentStore
    ) throws {
        guard schema2ColdNotificationDrainReceipt == nil,
              schema2ColdNotificationSource === source,
              schema2ColdNotificationControl === control,
              let intent = try store.load(),
              intent.phase == .sessionActivated,
              intent.eraseID == source.eraseID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPublishedRosterControlOwner(store: store)
        try receipt.requireBound(to: control,
            operationID: source.eraseID)
        schema2ColdNotificationDrainReceipt = receipt
    }

    func requireSchema2ColdNotificationDrained(
        store: EraseIntentStore
    ) throws {
        guard let source = schema2ColdNotificationSource,
              let control = schema2ColdNotificationControl,
              let receipt = schema2ColdNotificationDrainReceipt,
              let manifest = schema2ColdManifestOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdPublishedRosterControlOwner(store: store)
        try manifest.requireSchema2ColdNotificationSource(
            source, operation: self)
        try receipt.requireBound(to: control,
            operationID: source.eraseID)
    }

    /// The semantic source FDs remain held through durable roster creation.
    /// They are checked-closed once, before the first generation unlink; the
    /// immutable record then supplies all partial-cut authority.
    func closeSchema2ColdValidatedSourcesForDeletion(
        roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore
    ) throws {
        try requireSchema2ColdRosterStepOwner(
            roster: roster, store: store)
        guard !schema2ColdDeletionSourcesClosed,
              let sources = schema2ColdRetiredSources,
              let validated = schema2ColdValidatedGenerationTrees,
              let absent = schema2ColdFirstAbsentGenerationIDs,
              Set(validated.keys).union(absent)
                == Set(roster.record.frozenGenerationIDs.compactMap(
                    UUID.init(uuidString:))) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if schema2ColdRetainedOriginalSource != nil {
            try closeSchema2ColdRetainedSourceChecked()
        }
        for id in sources.keys.sorted(by: {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }) {
            guard let source = sources[id],
                  let attempt = schema2ColdRetiredPrivateAttempts[id],
                  attempt.isCheckedClosed else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try requireSchema2ColdRetiredSource(source)
            try source.closeChecked()
        }
        schema2ColdDeletionSourcesClosed = true
    }

    func retainSchema2ColdDeletionExecutor(
        _ executor: EraseSchema2ColdCheckedDeletionExecutorV1,
        roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore
    ) throws {
        if schema2ColdObservedReplayRoster == nil {
            try requireSchema2ColdRosterStepOwner(
                roster: roster, store: store)
            guard schema2ColdDeletionSourcesClosed else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        } else {
            try requireSchema2ColdRosterObservationOwner(store: store)
            guard let observed = schema2ColdObservedReplayRoster,
                  observed.canonicalBytes == roster.canonicalBytes,
                  observed.recordFileFact == roster.recordFileFact,
                  schema2ColdRetainedOriginalSource == nil,
                  schema2ColdRetiredSources == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            schema2ColdDeletionSourcesClosed = true
        }
        guard schema2ColdDeletionExecutor == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        schema2ColdDeletionExecutor = executor
    }

    var hasSchema2ColdDeletionSourcesClosed: Bool {
        schema2ColdDeletionSourcesClosed
    }

    var hasSchema2ColdDeletionExecutor: Bool {
        schema2ColdDeletionExecutor != nil
    }

    func requireSchema2ColdDeletionExecutor(
        roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore
    ) throws -> EraseSchema2ColdCheckedDeletionExecutorV1 {
        guard let executor = schema2ColdDeletionExecutor else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRosterStepOwner(
            roster: roster, store: store)
        try requireSchema2ColdDeletionExecutor(executor)
        return executor
    }

    func requireSchema2ColdDeletionExecutor(
        _ executor: EraseSchema2ColdCheckedDeletionExecutorV1
    ) throws {
        guard schema2ColdDeletionSourcesClosed,
              schema2ColdDeletionExecutor === executor,
              let roster = schema2ColdPublishedRoster,
              let store = schema2ColdIntentStore else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdRosterStepOwner(
            roster: roster, store: store)
    }

    /// A Store roster write has changed only its own held Erase directory,
    /// so its generic `load()` cannot run until the checked root projection
    /// finishes. This narrower in-flight reproof does not read that root or
    /// grant a second publication; Store still checks its exact old leaves,
    /// temporary inode, canonical bytes and names before each effect.
    func requireSchema2ColdRosterEffectOwner(
        store: EraseIntentStore
    ) throws {
        try requireServiceAccess()
        try requireSchema2ColdIntentStore(store)
        try requireSchema2ColdOriginalAuthority()
        guard let exclusion = schema2ColdPhysicalExclusion,
              let identity = schema2ColdSupportIdentity,
              let registry, let activity = schema2ColdActivity,
              let manifest = schema2ColdManifestOwner,
              let seal = schema2ColdRosterPublicationSeal,
              schema2ColdActivatedTargetSession != nil,
              schema2ColdTargetReaderHandle != nil,
              schema2ColdValidatedGenerationTrees != nil,
              !schema2ColdRosterPublished else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try registry.requireEraseSchema2ColdExcluded(
            operation: self, activity: activity)
        try requireSchema2ColdTargetReaderTokenCensus(
            registry: registry)
        try manifest.requireSchema2ColdRosterSourceFactsDuringPublication(
            seal: seal, operation: self)
    }

    fileprivate var hasSchema2ColdActivatedForward: Bool {
        schema2ColdPointerPhasePublished
            && schema2ColdPublishedIntent != nil
    }

    func retainSchema2ColdTargetContinuation(
        _ value: EraseSchema2ColdTargetContinuationV1
    ) throws {
        try requireServiceAccess()
        guard schema2ColdTargetContinuation == nil,
              schema2ColdTargetValidationAttempt == nil,
              schema2ColdOriginalContinuation == nil
                || schema2ColdOriginalValidationComplete,
              let source = schema2ColdTargetSource,
              source.generationID == value.intent.newGenerationID,
              schema2ColdManifestOwner != nil,
              schema2ColdIntentStore != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdTargetSource(source)
        schema2ColdTargetContinuation = value
    }

    func requireSchema2ColdTargetContinuation() throws
        -> (EraseSchema2ColdTargetContinuationV1,
            EraseIntentStore, EraseSchema2ColdManifestOwnerV1,
            EraseSchema2ColdTargetSourceV1,
            EraseSchema2ColdPhysicalExclusionV1,
            GenerationLeaseRegistryV1?,
            GenerationTemporalActivityHandleV1?) {
        try requireServiceAccess()
        guard let continuation = schema2ColdTargetContinuation,
              schema2ColdOriginalContinuation == nil
                || schema2ColdOriginalValidationComplete,
              let store = schema2ColdIntentStore,
              !schema2ColdIntentStoreClosed,
              let manifest = schema2ColdManifestOwner,
              !schema2ColdManifestOwnerClosed,
              let source = schema2ColdTargetSource,
              !schema2ColdTargetSourceClosed,
              let exclusion = schema2ColdPhysicalExclusion,
              !schema2ColdPhysicalExclusionClosed,
              let identity = schema2ColdSupportIdentity,
              source.generationID == continuation.intent.newGenerationID,
              (registry == nil) == (schema2ColdActivity == nil) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdIntentStore(store)
        try requireSchema2ColdManifestOwner(manifest)
        try requireSchema2ColdTargetSource(source)
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        if let registry { try requireConstructedSchema2ColdRegistry(registry) }
        return (continuation, store, manifest, source, exclusion,
            registry, schema2ColdActivity)
    }

    fileprivate var hasSchema2ColdTargetContinuation: Bool {
        schema2ColdTargetContinuation != nil
    }

    func requireSchema2ColdTargetValidationAttempt(
        _ expected: EraseSchema2ColdTargetValidationAttemptV1
    ) throws {
        guard let source = schema2ColdTargetSource else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSchema2ColdTargetSource(source)
        guard schema2ColdTargetValidationAttempt === expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func closeSchema2ColdManifestOwnerChecked() throws {
        try requireServiceAccess()
        guard let schema2ColdManifestOwner,
              !schema2ColdManifestOwnerClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try schema2ColdManifestOwner.closeChecked(operation: self)
        schema2ColdManifestOwnerClosed = true
    }

    func requireSchema2ColdIntentStore(_ store: EraseIntentStore) throws {
        try requireLive()
        guard schema2ColdIntentStore === store,
              !schema2ColdIntentStoreClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func closeSchema2ColdIntentStoreChecked() throws {
        try requireServiceAccess()
        guard let schema2ColdIntentStore,
              !schema2ColdIntentStoreClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try schema2ColdIntentStore.sealBorrowedColdAndCloseObserverChecked(operation: self)
        schema2ColdIntentStoreClosed = true
    }

    fileprivate var hasSchema2ColdIntentStore: Bool {
        schema2ColdIntentStore != nil
    }

    func retainEmptyNoWorkObservation(
        _ snapshot: EraseColdExistingControlObservationV1.Snapshot
    ) throws {
        try requireServiceAccess()
        guard snapshot.eraseRootExists, snapshot.intent == nil,
              snapshot.preparation == nil,
              coldControlObservation != nil,
              emptyNoWorkObservation == nil,
              !coldControlObservationClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        emptyNoWorkObservation = snapshot
    }

    fileprivate func reproveEmptyNoWorkDuringService() throws {
        try requireServiceAccess()
        guard let snapshot = emptyNoWorkObservation,
              let coldControlObservation,
              !coldControlObservationClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try coldControlObservation.requireCaptured(snapshot, operation: self)
    }

    func requireEmptyNoWorkPublicationAccess(
        _ observation: EraseColdExistingControlObservationV1,
        executionID: UUID, coordinator: StoreSessionCoordinator
    ) throws {
        guard let router, !serviceFrame, !coldControlObservationClosed,
              coldControlObservation === observation,
              emptyNoWorkObservation != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireEmptyNoWorkPublication(
            self, executionID: executionID, coordinator: coordinator)
    }

    fileprivate func reproveEmptyNoWorkForPublication(
        executionID: UUID, coordinator: StoreSessionCoordinator,
        close: Bool
    ) throws {
        guard let snapshot = emptyNoWorkObservation,
              let coldControlObservation,
              !coldControlObservationClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try coldControlObservation.requireEmptyForPublication(
            snapshot, operation: self, executionID: executionID,
            coordinator: coordinator)
        if close {
            try coldControlObservation.closeChecked()
            coldControlObservationClosed = true
        }
    }

    func requireC05ColdJournalReader(
        _ reader: EraseC05ColdPreparationJournalReaderV1
    ) throws {
        try requireLive()
        guard serviceFrame, !admissionSealed,
              !c05ColdJournalReaderClosed,
              c05ColdJournalReader === reader else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// The C05 store may enter its no-repair relaunch mode only from the
    /// exact preparation held by this startup operation. A copied UUID or a
    /// caller-supplied C05 record does not confer effect authority.
    func requireC05ColdPending(
        _ pending: EraseC05JobDrainV3
    ) throws -> UUID {
        try requireServiceAccess()
        guard let c05ColdJournalReader, !c05ColdJournalReaderClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let current = try c05ColdJournalReader
            .currentPredecessorPreparation(operation: self)
        guard current.c05JobDrainV3 == pending,
              pending.phase == .pending else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try requireC05ColdPhase(current, phase: .pending)
    }

    func requireC05ColdPhase(
        _ expected: ErasePreparationV2,
        phase: EraseC05JobDrainV3.Phase
    ) throws -> UUID {
        try requireServiceAccess()
        guard let c05ColdJournalReader, !c05ColdJournalReaderClosed,
              let drain = expected.c05JobDrainV3,
              drain.phase == phase, expected.targetPointer == nil,
              drain.sourceGenerationID == expected.oldPointer.generationID,
              try c05ColdJournalReader
                .currentPredecessorPreparation(operation: self) == expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return operationID
    }

    func retainC05ColdJobStore(_ store: LocalJobStoreV1) throws {
        try requireServiceAccess()
        guard c05ColdJobStore == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // The cold operation holds the actor before its first fallible
        // no-repair observation. A failed construction or checked close must
        // never make its physical owner disappear with a local stack frame.
        c05ColdJobStore = store
    }

    func requireC05ColdJobStore(_ store: LocalJobStoreV1) throws {
        try requireServiceAccess()
        guard c05ColdJobStore === store else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainC05ColdRunner(
        _ runner: ResumableLocalJobRunnerV1,
        store: LocalJobStoreV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireC05ColdJobStore(store)
        try requireConstructedC05ColdRegistry(expected)
        guard c05ColdRunner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdRunner = runner
    }

    func requireC05ColdRunner(
        _ runner: ResumableLocalJobRunnerV1,
        store: LocalJobStoreV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireC05ColdJobStore(store)
        try requireConstructedC05ColdRegistry(expected)
        guard c05ColdRunner === runner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainC05ColdSourceDrainWitness(
        _ witness: EraseC05ColdSourceDrainWitnessV1,
        expected: ErasePreparationV2,
        registry: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(registry)
        _ = try requireC05ColdPhase(expected, phase: .drained)
        guard c05ColdRunner != nil, c05ColdJobStore != nil,
              c05ColdSourceDrainWitness == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdSourceDrainWitness = witness
    }

    func requireC05ColdSourceDrainWitness(
        _ witness: EraseC05ColdSourceDrainWitnessV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard c05ColdSourceDrainWitness === witness,
              c05ColdRunner != nil, c05ColdJobStore != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireC05ColdDrainedLeaseCensus(
        _ leases: [GenerationLeaseTokenV1],
        expected: ErasePreparationV2,
        witness: EraseC05ColdSourceDrainWitnessV1,
        registry: GenerationLeaseRegistryV1
    ) throws {
        _ = try requireC05ColdPhase(expected, phase: .drained)
        try requireC05ColdSourceDrainWitness(witness, registry: registry)
        let writer = c05ColdWriterAllocation?.coldPublishedToken
        guard leases.filter({ $0.role == .writer })
                == (writer.map { [$0] } ?? []),
              leases.allSatisfy({ $0.role == .writer || $0.role == .reader }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try inventory.requireColdC05SourceCensus(
            leases.filter { $0.role == .reader },
            registry: registry, witness: witness)
    }

    func closeC05ColdJournalReaderChecked() throws {
        try requireLive()
        guard serviceFrame, !c05ColdJournalReaderClosed,
              let c05ColdJournalReader else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try c05ColdJournalReader.closeChecked()
        c05ColdJournalReaderClosed = true
    }

    func retainFrozenC05PointerReader(
        _ reader: EraseC05FrozenPointerReaderV1
    ) throws {
        try requireLive()
        guard serviceFrame, !admissionSealed,
              frozenC05PointerReader == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        frozenC05PointerReader = reader
    }

    func requireFrozenC05PointerReader(
        _ reader: EraseC05FrozenPointerReaderV1
    ) throws {
        try requireLive()
        guard serviceFrame, !admissionSealed,
              !frozenC05PointerReaderClosed,
              frozenC05PointerReader === reader else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func closeFrozenC05PointerReaderChecked() throws {
        try requireLive()
        guard serviceFrame, !frozenC05PointerReaderClosed,
              let frozenC05PointerReader else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try frozenC05PointerReader.closeChecked()
        frozenC05PointerReaderClosed = true
        // Retain the now-inert exact owner as checked-close evidence.
    }

    func retainFrozenC05ManifestReader(_ reader: EraseC05FrozenManifestReaderV1) throws {
        try requireLive()
        guard serviceFrame, frozenC05ManifestReader == nil,
              !frozenC05ManifestReaderClosed, !admissionSealed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // The Router retains this operation before the first descriptor open.
        frozenC05ManifestReader = reader
    }

    func retainC05ColdRegistryConstruction(
        _ construction: EraseC05ColdRegistryConstructionV1) throws {
        try requireLive()
        guard serviceFrame, !admissionSealed,
              c05ColdRegistryConstruction == nil, registry == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdRegistryConstruction = construction
    }

    func requireC05ColdRegistryConstruction() throws {
        try requireLive()
        guard serviceFrame, !admissionSealed,
              c05ColdRegistryConstruction != nil, registry == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// Called synchronously immediately after the no-repair constructor
    /// transfers ownership. requireC05ColdRegistryConstruction ran first.
    func retainConstructedC05ColdRegistry(_ value: GenerationLeaseRegistryV1) {
        registry = value
    }

    func requireConstructedC05ColdRegistry(_ expected: GenerationLeaseRegistryV1) throws {
        try requireLive()
        guard serviceFrame, c05ColdRegistryConstruction != nil,
              registry === expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainC05ColdWriterActivityAcquisition(
        _ value: EraseC05ColdWriterActivityAcquisitionV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard c05ColdWriterActivities.count < 2,
              !c05ColdWriterActivities.contains(where: { $0 === value }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdWriterActivities.append(value)
    }

    func retainEraseC05ColdWriterAllocation(
        _ value: EraseC05ColdWriterAllocationV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard c05ColdWriterAllocation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdWriterAllocation = value
    }

    func requireEraseC05ColdWriterAllocation(
        _ expected: EraseC05ColdWriterAllocationV1,
        registry expectedRegistry: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expectedRegistry)
        guard c05ColdWriterAllocation === expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainC05ColdPredecessorProbe(
        _ probe: EraseC05ColdPredecessorProbeV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard serviceFrame, !admissionSealed,
              c05ColdPredecessorProbe == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdPredecessorProbe = probe
    }

    func requireC05ColdPredecessorProbe(
        _ probe: EraseC05ColdPredecessorProbeV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard serviceFrame, !admissionSealed,
              c05ColdPredecessorProbe === probe else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func retainedC05ColdPredecessorProbe(
        registry expected: GenerationLeaseRegistryV1
    ) throws -> EraseC05ColdPredecessorProbeV1 {
        try requireConstructedC05ColdRegistry(expected)
        guard serviceFrame, !admissionSealed,
              let c05ColdPredecessorProbe else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return c05ColdPredecessorProbe
    }

    func retainC05ColdPredecessorReplacement(
        _ attempt: EraseC05ColdPredecessorReplacementV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard serviceFrame, !admissionSealed,
              c05ColdPredecessorProbe != nil,
              c05ColdPredecessorReplacement == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdPredecessorReplacement = attempt
    }

    func requireC05ColdPredecessorReplacement(
        _ attempt: EraseC05ColdPredecessorReplacementV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard serviceFrame, !admissionSealed,
              c05ColdPredecessorReplacement === attempt else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func recordC05ColdPredecessorCheckedCompletion(
        journal: EraseC05ColdPreparationJournalReaderV1,
        probe: EraseC05ColdPredecessorProbeV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireC05ColdJournalReader(journal)
        try requireC05ColdPredecessorProbe(probe, registry: expected)
        guard !c05ColdPredecessorCheckedComplete,
              let record = try journal.currentPredecessorPreparation(
                operation: self).coldPredecessorReclaim,
              record.phase == .guardsRemoved else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // A fresh cold process may resume from an exact durable
        // REGISTRY_PUBLISHED marker without the predecessor replacement FD.
        // A retained attempt from this process, however, must have closed.
        try c05ColdPredecessorReplacement?.requireCheckedClosed()
        try probe.requireCheckedClosed()
        c05ColdPredecessorCheckedComplete = true
    }

    func recordC05ColdPredecessorRestoredTerminal(
        journal: EraseC05ColdPreparationJournalReaderV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireC05ColdJournalReader(journal)
        try requireConstructedC05ColdRegistry(expected)
        guard serviceFrame, !admissionSealed,
              !c05ColdPredecessorCheckedComplete,
              c05ColdPredecessorProbe == nil,
              c05ColdPredecessorReplacement == nil,
              let record = try journal.currentPredecessorPreparation(
                operation: self).coldPredecessorReclaim,
              record.phase == .guardsRemoved else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        c05ColdPredecessorCheckedComplete = true
    }

    func requireOrdinaryColdReaderAdmission() throws {
        try requireLive()
        guard c05ColdJournalReader == nil,
              !c05ColdPredecessorCheckedComplete else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireC05ColdPredecessorCheckedCompletion(
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard serviceFrame, !admissionSealed,
              c05ColdPredecessorCheckedComplete,
              let c05ColdJournalReader,
              let record = try c05ColdJournalReader
                .currentPredecessorPreparation(operation: self)
                .coldPredecessorReclaim,
              record.phase == .guardsRemoved else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try c05ColdPredecessorReplacement?.requireCheckedClosed()
        try c05ColdPredecessorProbe?.requireCheckedClosed()
    }

    func retainC05ColdRegistryObservation(
        _ attempt: EraseC05ColdRegistryObservationAttemptV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        guard serviceFrame, !admissionSealed,
              c05ColdRegistryObservations.count < 64,
              !c05ColdRegistryObservations.contains(where: { $0 === attempt }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Retain before the first open; an uncertain close remains with this
        // exact operation and cannot be retried through a reused FD integer.
        c05ColdRegistryObservations.append(attempt)
    }

    func requireEraseC05ColdWriterCensus(
        _ leases: [GenerationLeaseTokenV1],
        writer: GenerationLeaseTokenV1?,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        try requireConstructedC05ColdRegistry(expected)
        try authorization.withMediaRecovery {
            try requireLive()
            guard serviceFrame, !admissionSealed,
                  leases.filter({ $0.role == .writer })
                    == (writer.map({ [$0] }) ?? []) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try inventory.requireColdPreparationCensus(
                leases.filter { $0.role == .reader }, registry: expected)
        }
    }

    func requireFrozenC05ManifestReader(_ reader: EraseC05FrozenManifestReaderV1) throws {
        try requireLive()
        guard serviceFrame, frozenC05ManifestReader === reader,
              !frozenC05ManifestReaderClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func closeFrozenC05ManifestReaderChecked() throws {
        try requireLive()
        guard serviceFrame, !frozenC05ManifestReaderClosed,
              let frozenC05ManifestReader else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try frozenC05ManifestReader.closeChecked()
        frozenC05ManifestReaderClosed = true
        // Keep the inert owner retained as exact closure evidence.
    }

    private func requireLive() throws {
        guard let router else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireColdPreparation(self)
    }

    func beginServiceFrame() async throws {
        try requireLive()
        guard !serviceFrame, !admissionSealed, !retirementAcquisitionStarted,
              prepared == nil, rollback == nil, !advancingCleanup else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await authorization.validate()
        try requireLive()
        // Authorization suspends. Another caller may have entered or sealed
        // this owner while suspended; liveness alone does not reserve a frame.
        guard !serviceFrame, !admissionSealed, !retirementAcquisitionStarted,
              prepared == nil, rollback == nil, !advancingCleanup else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        serviceFrame = true
    }

    func beginRollbackFrame() async throws {
        try requireLive()
        guard !serviceFrame, !admissionSealed, !retirementAcquisitionStarted,
              prepared == nil, rollback != nil, advancingCleanup else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await authorization.validate()
        try requireLive()
        guard !serviceFrame, !admissionSealed, !retirementAcquisitionStarted,
              prepared == nil, rollback != nil, advancingCleanup else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        serviceFrame = true
    }

    func requireServiceAccess() throws {
        try requireLive()
        guard serviceFrame, !admissionSealed, !retirementAcquisitionStarted else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try authorization.withMediaRecovery { try requireLive() }
    }

    func endServiceFrame() { serviceFrame = false }

    func requireInventoryBinding(_ value: EraseReaderRetirementInventoryV1) throws {
        try requireLive()
        guard value === inventory, !serviceFrame, !admissionSealed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func registerRegistry(_ value: GenerationLeaseRegistryV1,
        factory actualFactory: StoreGenerationFactory, inventory actual: EraseReaderRetirementInventoryV1) throws {
        try requireLive()
        guard serviceFrame, !admissionSealed, actual === inventory,
              factory.sharesRegistryProvider(with: actualFactory),
              registry == nil || registry === value else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        registry = value
    }

    func requireColdPreparationReaderAllocation(_ allocation: GenerationLeaseAllocationAttemptV1,
        registry expected: GenerationLeaseRegistryV1) throws {
        try authorization.withMediaRecovery {
            try requireLive()
            guard serviceFrame, !admissionSealed, !retirementAcquisitionStarted,
                  registry === expected, allocation.matches(registry: expected),
                  inventory.containsColdPreparationAllocation(allocation) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
    }

    func requireColdPreparationLeaseCensus(_ leases: [GenerationLeaseTokenV1],
        registry expected: GenerationLeaseRegistryV1) throws {
        try authorization.withMediaRecovery {
            try requireLive()
            guard serviceFrame, !admissionSealed, !retirementAcquisitionStarted,
                  registry === expected else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try inventory.requireColdPreparationCensus(leases, registry: expected)
        }
    }

    func requireFailureWitnessRegistration(inventory actual: EraseReaderRetirementInventoryV1,
        registry expected: GenerationLeaseRegistryV1) throws {
        guard let router, !serviceFrame, !admissionSealed, !retirementAcquisitionStarted,
              failureWitness == nil, actual === inventory, registry === expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireRetainedColdPreparation(self)
    }

    func disposeFailedReaders() throws {
        guard !serviceFrame, !retirementAcquisitionStarted else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // A V3 owner is a forward-only cold continuation. Generic failed
        // reader disposal would erase its exact descriptor/phase provenance.
        guard c05ColdJournalReader == nil,
              frozenC05PointerReader == nil,
              frozenC05ManifestReader == nil,
              c05ColdRegistryConstruction == nil,
              c05ColdWriterActivities.isEmpty,
              c05ColdWriterAllocation == nil,
              c05ColdRegistryObservations.isEmpty,
              c05ColdPredecessorProbe == nil,
              c05ColdPredecessorReplacement == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard let registry else {
            try inventory.requireNoConstructedResourcesForAbort()
            return
        }
        if failureWitness == nil {
            let witness = try inventory.sealForColdPreparationFailure(operation: self, registry: registry)
            failureWitness = witness
            admissionSealed = true
        }
        guard let failureWitness else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try failureWitness.disposeOwnedAllocations()
    }

    func restartAfterDisposedReaders() throws {
        try requireLive()
        guard !serviceFrame, !retirementAcquisitionStarted, prepared == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let failureWitness {
            try failureWitness.requireDisposed()
            settledWitnesses.append(failureWitness)
        } else { try inventory.requireNoConstructedResourcesForAbort() }
        inventory = EraseReaderRetirementInventoryV1()
        inventoryBound = false
        failureWitness = nil
        admissionSealed = false
    }

    func retainRollback(_ value: EraseColdPreparationRollbackV1) throws {
        try requireLive()
        guard serviceFrame, rollback == nil, prepared == nil, !retirementAcquisitionStarted else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        rollback = value
    }

    func requireRollbackRemoval(_ value: ErasePreparedGenerationDiscardV1,
        factory expected: StoreGenerationFactory) throws {
        try requireLive()
        guard serviceFrame, !admissionSealed, !retirementAcquisitionStarted,
              factory.sharesRegistryProvider(with: expected), let rollback else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try rollback.requireSourceRemoval(value)
    }

    func advanceRollback() async throws -> Bool {
        try requireLive()
        guard !serviceFrame, !advancingCleanup, let rollback else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        advancingCleanup = true
        defer { advancingCleanup = false }
        try requireStartupContinuation()
        let completed = try await rollback.advance(operation: self)
        try requireStartupContinuation()
        return completed
    }

    func requireFailureDisposal(witness: EraseColdPreparationFailureDrainWitnessV1,
        registry expected: GenerationLeaseRegistryV1) throws {
        guard let router, admissionSealed, !serviceFrame, !retirementAcquisitionStarted,
              failureWitness === witness, registry === expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try router.requireRetainedColdPreparation(self)
    }
}

extension StartupRouter {
    fileprivate func requireRetainedColdPreparation(_ value: EraseColdPreparationOperationV1) throws {
        guard coldErasePreparation === value, value.router === self else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    fileprivate func requireColdPreparation(_ value: EraseColdPreparationOperationV1) throws {
        try requireRetainedColdPreparation(value)
        try requireCurrentOperation(value.executionID)
        guard operationKind == .startup, operationOwnedWriter == nil, publishedWriter == nil,
              preparedStartup == nil, maintenanceRestoreSession == nil, maintenanceEraseSession == nil,
              deferredEraseCoordinator == nil, pendingErasedActivation == nil,
              pendingWriterLeaseReleases.isEmpty, pendingCoordinatorReleases.isEmpty,
              originalOperations.isEmpty, temporalNormalizationOperation == nil,
              temporalColdOperation == nil else { throw AppAccessContractFailureV1.staleAttempt }
    }

    /// This narrower continuation is valid after ordinary startup has
    /// constructed its still-unpublished writer. The general cold preparation
    /// guard intentionally rejects that state.
    fileprivate func requireEmptyNoWorkPublication(
        _ value: EraseColdPreparationOperationV1,
        executionID: UUID, coordinator: StoreSessionCoordinator
    ) throws {
        try requireRetainedColdPreparation(value)
        guard operationKind == .startup,
              let owner = operationOwnedWriter,
              owner.coordinator === coordinator,
              owner.writer === coordinator.workspaceWriter,
              publishedWriter == nil,
              maintenanceRestoreSession == nil,
              maintenanceEraseSession == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireCurrentOperation(executionID, owner: owner)
    }

    private func reproveEmptyNoWorkBeforePublication(
        operation: UUID, owner: OwnedWriter, close: Bool
    ) throws {
        guard let cold = coldErasePreparation else { return }
        guard cold.hasEmptyNoWorkObservation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try cold.reproveEmptyNoWorkForPublication(
            executionID: operation, coordinator: owner.coordinator,
            close: close)
        if close { coldErasePreparation = nil }
    }

    private func reproveEmptyNoWorkBeforeOrdinaryEffects() async throws {
        guard let cold = coldErasePreparation else { return }
        guard cold.hasEmptyNoWorkObservation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try await cold.beginServiceFrame()
        do {
            try cold.reproveEmptyNoWorkDuringService()
        } catch {
            cold.endServiceFrame()
            throw error
        }
        cold.endServiceFrame()
    }
}


extension StartupRouter {
    private func reconcileColdErase(operation: UUID, authorization: StartupAuthorization?,
        service: EraseAllService) async throws -> EraseFreshAdoptionOwnerV1? {
        try requireCurrentOperation(operation)
        // An absent namespace needs no content authority or invented owner.
        // A present/malformed namespace can only enter genuine startup access.
        if coldErasePreparation == nil {
            var facts = stat()
            let path = applicationSupportURL.appendingPathComponent("FieldEvidenceErase").path
            if Darwin.lstat(path, &facts) != 0 {
                guard errno == ENOENT else { throw EraseAllServiceError.invalidAuthority }
                return nil
            }
            guard facts.st_mode & S_IFMT == S_IFDIR else { throw EraseAllServiceError.invalidAuthority }
        }
        guard let authorization else { throw AppAccessContractFailureV1.accessDenied }
        let cold: EraseColdPreparationOperationV1
        if let retained = coldErasePreparation {
            cold = retained
            try cold.resume(executionID: operation, authorization: authorization)
        } else {
            cold = EraseColdPreparationOperationV1(router: self, operationID: operation,
                authorization: authorization, factory: generationFactory)
            coldErasePreparation = cold
        }
        if cold.hasEmptyNoWorkObservation {
            // A previous startup may have suspended after the no-intent
            // observation. Recheck the same retained owner before ordinary
            // source opening; never reconstruct a competing reader.
            try await cold.beginServiceFrame()
            do {
                try cold.reproveEmptyNoWorkDuringService()
            } catch {
                cold.endServiceFrame()
                throw error
            }
            cold.endServiceFrame()
        } else if !cold.hasPreparedCleanup && !cold.hasRollback {
            // An incomplete schema-2 frame has transferred actual Erase-root
            // descriptors. Only a phase-bound private target continuation
            // may resume those exact owners; a failed earlier constructor
            // cannot be forgotten or reconstructed as a new cold attempt.
            if cold.hasSchema2ColdIntentStore {
                let captured = try cold.configuredFactory()
                let configured = try service.configuredForColdRetirement(
                    factory: captured, inventory: cold.inventory)
                if cold.hasSchema2ColdActivatedForward {
                    try await configured.resumeSchema2ColdActivatedForward(
                        operation: cold)
                } else if cold.hasSchema2ColdOriginalContinuation {
                    try await configured.resumeSchema2ColdRetainedSourceValidation(
                        operation: cold)
                } else if cold.hasSchema2ColdRetiredValidationPending {
                    try await configured.resumeSchema2ColdRetiredSourcesValidation(
                        operation: cold)
                } else if cold.hasSchema2ColdActivatedEntryContinuation {
                    try await configured.resumeSchema2ColdActivatedEntry(
                        operation: cold)
                } else if cold.hasSchema2ColdPreactivationContinuation {
                    try await configured.resumeSchema2ColdPreactivationTargetValidation(
                        operation: cold)
                } else if cold.hasSchema2ColdTargetContinuation {
                    try await configured.resumeSchema2ColdTargetValidation(
                        operation: cold)
                } else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            // A failed prior constructor cannot be forgotten on retry.
            try cold.disposeFailedReaders()
            try cold.restartAfterDisposedReaders()
            let captured = try cold.configuredFactory()
            let configured = try service.configuredForColdRetirement(factory: captured,
                inventory: cold.inventory)
            _ = try await configured.prepareColdRetirement(diagnosticsStore: diagnosticsStore, operation: cold)
            try cold.requireStartupContinuation()
        }
        if cold.hasRollback {
            guard try await cold.advanceRollback() else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try cold.requireStartupContinuation()
            coldErasePreparation = nil
            return nil
        }
        guard cold.hasPreparedCleanup else {
            try cold.requireNoWork()
            if !cold.hasEmptyNoWorkObservation {
                coldErasePreparation = nil
            }
            return nil
        }
        guard try await cold.advancePreparedCleanup() else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try cold.requireStartupContinuation()
        let (retirement, proof) = try cold.completedRetirement()
        let fresh: EraseFreshAdoptionOwnerV1
        if let retained = freshEraseAdoption {
            guard case .cold(let actual) = retained.origin, actual === cold,
                  retained.retirement === retirement, retained.proof === proof else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            fresh = retained
            if fresh.phase == .failed || fresh.phase == .disposing { try fresh.disposeFailedConstruction() }
            if fresh.phase == .disposed {
                try fresh.restartColdAfterSuccessfulDisposal(executionID: operation, authorization: authorization)
            } else {
                try fresh.authorizeColdContinuation(executionID: operation, authorization: authorization)
            }
        } else {
            let actualFactory = try generationFactory.freshForEraseAdoption(retirement: proof)
            fresh = EraseFreshAdoptionOwnerV1(router: self, cold: cold, retirement: retirement,
                proof: proof, executionID: operation, authorization: authorization, factory: actualFactory)
            freshEraseAdoption = fresh
        }
        generationFactory = fresh.factory
        return fresh
    }

    private func consumeColdStartupOwnership(_ fresh: EraseFreshAdoptionOwnerV1,
        session: StoreGenerationSession, coordinator: StoreSessionCoordinator) throws {
        guard case .cold = fresh.origin, let ordinary = fresh.ordinaryFactory else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try fresh.consumePublication(session: session, coordinator: coordinator, factory: ordinary)
        generationFactory = ordinary
        freshEraseAdoption = nil
        coldEraseRetirement = nil
        coldErasePreparation = nil
    }
}

#if DEBUG
extension StartupRouter {
    /// Injects the actual service's existing fault points into the genuine
    /// startup route. It cannot mint a ticket or skip access/ownership checks.
    func retryColdEraseForTesting(service: EraseAllService,
        accessGate: any AppAccessGatePortV1) async throws {
        let authorization = try await startupAuthorization(accessGate)
        await runStartup(authorization: authorization, coldEraseService: service)
        try await authorization.validate()
        if let lastStartupAccessFailure { throw lastStartupAccessFailure }
    }
}
#endif
@MainActor final class OriginalEraseNotificationTerminalCloseWitnessV1 {
    private weak var control: AppLockNotificationControlStoreV1?
    private let receipt: OriginalEraseNotificationEffectReceiptV1
    private let marker: OriginalEraseNotificationMarkerPublicationReceiptV1
    private let removal: OriginalEraseNotificationRecordRemovalReceiptV1
    private let absence: OriginalEraseNotificationOSAbsenceReceiptV1
    private let eraseID: UUID
    private var closeAttempted = false
    private(set) var checkedClosed = false

    fileprivate init(control: AppLockNotificationControlStoreV1,
        receipt: OriginalEraseNotificationEffectReceiptV1,
        marker: OriginalEraseNotificationMarkerPublicationReceiptV1,
        removal: OriginalEraseNotificationRecordRemovalReceiptV1,
        absence: OriginalEraseNotificationOSAbsenceReceiptV1,
        eraseID: UUID) {
        self.control = control
        self.receipt = receipt
        self.marker = marker
        self.removal = removal
        self.absence = absence
        self.eraseID = eraseID
    }

    func requireBeforeClose(control: AppLockNotificationControlStoreV1,
        eraseID: UUID) throws {
        guard !closeAttempted, !checkedClosed,
              self.control === control, self.eraseID == eraseID,
              marker.revocation == receipt.revocation,
              receipt.revocation == absence.revocation,
              marker.checkedSettled, removal.checkedSettled else {
            throw EraseAllServiceError.invalidAuthority
        }
        try removal.requireBound(control: control,
            absence: absence, marker: marker)
        try receipt.requireBound(control: control, operationID: eraseID)
    }

    func beginClose() throws {
        guard !closeAttempted, !checkedClosed else {
            throw EraseAllServiceError.invalidAuthority
        }
        closeAttempted = true
    }

    func finishCheckedClose(control: AppLockNotificationControlStoreV1) throws {
        guard closeAttempted, !checkedClosed,
              self.control === control,
              control.originalEraseCheckedCloseComplete else {
            throw EraseAllServiceError.invalidAuthority
        }
        checkedClosed = true
    }

    func requireClosed(control: AppLockNotificationControlStoreV1,
        eraseID: UUID) throws {
        guard checkedClosed, self.control === control,
              self.eraseID == eraseID,
              control.originalEraseCheckedCloseComplete else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

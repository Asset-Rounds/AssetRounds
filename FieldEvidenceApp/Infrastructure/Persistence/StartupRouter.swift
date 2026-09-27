import Foundation
import SwiftData
import SwiftUI

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

    private func reportStartupFailureForTesting(_ error: Error) {
        guard let observe = startupFailureDiagnosticForTesting else { return }
        let phase = runtimeObservation?.phase.rawValue ?? "unobserved"
        let errorType = String(reflecting: type(of: error))
        let policyMismatch = (error as? ProtectedFilePolicyError) == .resourceValueMismatch
        observe("phase=\(phase) type=\(errorType) resourceValueMismatch=\(policyMismatch)")
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
    }
    private let originalOperationOwner = OriginalOperationOwner()
    private var originalOperations: [UUID: OriginalOperationState] = [:]
    private var coldErasePreparation: EraseColdPreparationOperationV1?
    private var coldEraseRetirement: EraseColdRetirementAuthorityV1?
    private var retainedEraseRetirementOperation: EraseRouterOperationV1?
#if DEBUG
    private var abandonedOriginalEraseForColdRestart = false
    // The original registry guard and any uncertain release attempts remain
    // alive even if the test replaces every ordinary Router reference.
    private static var retainedOriginalEraseShutdownOwnersForTesting: [EraseRouterOperationV1] = []
    private static var retainedPostRetiredOriginalServicesForTesting: [EraseAllService] = []
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
        accessGate: AppAccessGateV1
    ) async throws -> OriginalOperationTicket {
        guard pendingEraseDrainProof == nil, !isRunning,
              pendingAbortedOriginalReaderRetirements.isEmpty,
              originalOperations.isEmpty else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        let authorization = try await startupAuthorization(accessGate)
        guard pendingEraseDrainProof == nil, !isRunning,
              pendingAbortedOriginalReaderRetirements.isEmpty,
              originalOperations.isEmpty else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        if let coordinator {
            guard coordinator.modelContext === sourceModelContext,
                  coordinator.generationID == sourceGenerationID else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        }
        guard try generationFactory.currentGenerationID() == sourceGenerationID else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        // This retention is an admission property, not a post-service
        // cleanup detail.  It therefore survives every suspended callback.
        retainsGenerationsUntilColdLaunch = true
        let operation = beginOperation(.restored, authorization: authorization)
        let mint = OriginalOperationMint()
        originalOperations[operation] = OriginalOperationState(
            kind: .restore, owner: originalOperationOwner, mint: mint,
            sourceGenerationID: sourceGenerationID,
            source: OriginalOperationSourceReference(
                coordinator: coordinator, modelContext: sourceModelContext
            ), authorization: authorization
        )
        return OriginalOperationTicket(owner: originalOperationOwner, mint: mint,
                                       operationID: operation)
    }

    func validateRestoreOperation(_ ticket: OriginalOperationTicket) async throws {
        let state = try await validateOriginalOperation(ticket, kind: .restore)
        try await state.authorization.validate()
    }

    /// Admission is intentionally separate from the service subject.  The
    /// service mints that subject immediately before its first effect; root
    /// passes this original token to the lifecycle exactly once at that edge.
    func beginEraseOperation(
        coordinator: StoreSessionCoordinator,
        accessGate: AppAccessGateV1
    ) async throws -> OriginalOperationTicket {
        guard !isRunning, pendingEraseDrainProof == nil,
              pendingAbortedOriginalReaderRetirements.isEmpty,
              originalOperations.isEmpty, resolvePendingWriterCleanup(),
              publishedWriter.map({ $0.coordinator === coordinator &&
                  $0.writer === coordinator.workspaceWriter }) ?? true else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        let authorization = try await startupAuthorization(accessGate)
        guard !isRunning, pendingEraseDrainProof == nil,
              pendingAbortedOriginalReaderRetirements.isEmpty,
              originalOperations.isEmpty, resolvePendingWriterCleanup(),
              publishedWriter.map({ $0.coordinator === coordinator &&
                  $0.writer === coordinator.workspaceWriter }) ?? true else {
            throw AppAccessContractFailureV1.staleAttempt
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
        guard ticket.owner === originalOperationOwner,
              let state = originalOperations[ticket.operationID],
              state.mint === ticket.mint,
              operationID == ticket.operationID || operationID == nil else { return }
        if let value = retainedEraseRetirementOperation {
            do { try value.requireNoRetirementResourcesForAbort() }
            catch { invalidateOperationAndPublishedWriter(); return }
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

        let operation = beginOperation(.startup, authorization: authorization)
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

#if DEBUG
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
                let result = try await generationFactory.openForStartup(validateContinuation: {
                    try await self.requireCurrentOperationAndAccess(operation)
                }, recoverOriginalSource: { authority in
                    try await self.requireCurrentOperationAndAccess(operation)
                    try await self.recoverOriginalSource(authority, operation: operation)
                    try await self.requireCurrentOperationAndAccess(operation)
                })
                try await requireCurrentOperationAndAccess(operation)
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
            do {
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
            do {
                try await retireCurrentPrivatePreparations(session: session, operation: operation, owner: owner)
                _ = try await FinalizationRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    workspaceWriter: owner.writer,
                    lifecycleProfileRegistry: coordinator.lifecycleProfileRegistry
                ).reconcile()
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
                _ = try await WholeSignDeletionService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager
                ).reconcile()
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
            await diagnosticsStore.prepare()
            try await requireCurrentOperationAndAccess(operation, owner: prepared.owner)
            try await installCommerceProcessor(operation: operation, owner: prepared.owner)
            try await requireCurrentOperationAndAccess(operation, owner: prepared.owner)
            if let captureOperationID = prepared.unadmittedEraseCaptureOperationID {
                try prepared.owner.coordinator.resumeWholeSignDeletionAfterAuthenticatedEraseReturn(
                    expectedWriter: prepared.owner.writer,
                    captureOperationID: captureOperationID)
            }
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
    ) async throws {
        try await activateRestoredSessionCore(session, coordinator: coordinator, ticket: ticket)
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
                try await retireCurrentPrivatePreparations(session: session, operation: operation, owner: owner)
                _ = try await FinalizationRecoveryService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    workspaceWriter: owner.writer,
                    lifecycleProfileRegistry: activeCoordinator.lifecycleProfileRegistry
                ).reconcile()
                try await requireCurrentOperationAndAccess(operation, owner: owner)
                _ = try await WholeSignDeletionService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    fileManager: fileManager
                ).reconcile()
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
        let store = FinalizationIntentStore(generationRootURL: session.generationRootURL,
            expectedGenerationRootIdentity: rootIdentity)
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
@MainActor
final class EraseRouterOperationV1 {
    fileprivate weak var router: StartupRouter?
    fileprivate let ticket: StartupRouter.OriginalOperationTicket
    let inventory: EraseReaderRetirementInventoryV1
    private var binding: EraseRetirementBindingV1?
    private var prepared: EraseCleanupAfterRetirementV1?
    private var drain: EraseSessionDrainWitnessV1?
    private var originalExclusion: StoreTemporalNormalizationExclusionV1?
    private var transferredExclusion: EraseRetirementExclusionV1?
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
    private var preparationServiceFrame = false
    private var preparationWriterAllocation: GenerationWriterAllocationAttemptV1?
    private weak var preparationTargetSession: StoreGenerationSession?
    private var preparationTargetRootURL: URL?
    private weak var preparationTargetWriter: WorkspaceWriterV1?
    private var preparationFailureWitness: ErasePreparationFailureDrainWitnessV1?
#if DEBUG
    private enum OriginalShutdownState { case active, poisoned, controlsTransferred, controlsReleased, uncertain }
    private var originalShutdownState = OriginalShutdownState.active
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
        try router.requireEraseRetirementOperation(self)
    }

#if DEBUG
    fileprivate func poisonInterruptedOriginalPreparation(
        sourceGenerationID: UUID, targetGenerationID: UUID
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
    }

    /// Durable pre-detach interruption keeps its constructed readers and
    /// possibly its installed target writer for the original-shutdown witness.
    /// No-effect abort disposal is deliberately a separate authority.
    fileprivate func poisonInterruptedDurableOriginalPreparation(
        sourceGenerationID: UUID, targetGenerationID: UUID,
        expectedFault: EraseAllFailurePoint
    ) throws {
        guard originalShutdownState == .active, !detached, !detaching,
              prepared == nil, drain == nil, originalExclusion == nil,
              transferredExclusion == nil, !startedExclusionAcquisition,
              !preparationServiceFrame, preparationFailureWitness == nil,
              let router, let registry = preparationRegistry,
              let source = preparationSourceWriter,
              source.token.ownerID == registry.ownerID,
              preparationFactory != nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        switch expectedFault {
        case .afterPreparedWrite, .afterPointerSwitch, .afterPointerPhaseWrite:
            guard preparationWriterPhase == .absent else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        case .afterSessionPhaseWrite:
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
        // sealForOriginalShutdown repeats the full registered owner census
        // before any EX transfer. This edge only forbids further effects.
        originalShutdownSourceGenerationID = sourceGenerationID
        originalShutdownTargetGenerationID = targetGenerationID
        originalShutdownState = .poisoned
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
        try witness.requireDrained(registry: registry)
        do {
            for reader in witness.preparationReaders {
                try reader.closeForOriginalEraseShutdown(proof: witness, activity: activity)
            }
            for reader in witness.capturedReaders {
                try witness.requireCapturedReader(reader, registry: registry)
                try reader.closeForOriginalEraseShutdown(witness: witness, activity: activity)
            }
            if let target = witness.preparationWriter {
                try target.closeForOriginalEraseShutdown(proof: witness, activity: activity)
            }
            if originalShutdownInstalled {
                try source.requireCheckedClosedForOriginalEraseShutdown(registry: registry)
                guard witness.preparationWriter?.allocatedHandle === current else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            } else {
                guard current === source else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
                try source.closeForOriginalEraseShutdown(witness: witness, activity: activity)
            }
            try witness.requireDrained(registry: registry)
            try registry.requireOriginalEraseShutdownLeaseCensus(witness: witness,
                activity: activity)
            try finalNoEffect?()
            try registry.closeOriginalEraseShutdownExclusion(
                witness: witness, activity: activity, physicalRoot: root)
            try registry.unlinkOriginalEraseShutdownOwnerGuard(witness: witness)
            try registry.finishOriginalEraseShutdownUnlinkedGuard(witness: witness)
            originalShutdownState = .controlsReleased
        } catch {
            // Any ambiguous close or post-unlink result remains terminal and
            // retains the exact owner. This path cannot mint cold readiness.
            originalShutdownState = .uncertain
            throw error
        }
    }

    fileprivate func finishCompletedAbortForColdRestart(
        service: EraseAllService,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard let registry = originalShutdownRegistry,
              let witness = originalShutdownWitness else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try finishInterruptedOriginalPreparationForColdRestart {
            try registry.requireCompletedAbortFinalNoEffectUnderOriginalShutdown(
                witness: witness, service: service,
                operation: self, receipt: receipt)
        }
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

    func requireRecoveryExecution(coordinator: StoreSessionCoordinator) throws {
        guard let router, !detached, prepared == nil else { throw AppAccessContractFailureV1.staleAttempt }
        try router.requireLiveEraseRecovery(self, coordinator: coordinator)
    }

    func requirePreparationRollback() throws {
        guard let router, preparationServiceFrame, !detached, !detaching,
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
        try requireEraseRetirementOperation(value)
        try service.requireCompletedAbortColdShutdownForTesting(
            expectedFault, operation: value, receipt: receipt)
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
            throw AppAccessContractFailureV1.staleAttempt
        }
        try value.requireNoRetirementResourcesForAbort()
        try value.poisonInterruptedOriginalPreparation(
            sourceGenerationID: state.sourceGenerationID,
            targetGenerationID: receipt.subject.newGenerationID)
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
        let drainID = try coordinator.closeProducerAdmissionForOriginalEraseShutdown()
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
        try await coordinator.awaitProducersForOriginalEraseShutdown(drainID)
        guard completedAbortShutdown?.operation === value,
              completedAbortShutdown?.drainID == drainID,
              completedAbortShutdown?.lifecycleReleased == true,
              completedAbortSourceRouteMatchesForTesting(
                  coordinator, liveTicket: nil) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        try held.service.requireCompletedAbortNoEffectForTesting(
            operation: value, receipt: receipt)
        let control = try coordinator.captureOriginalEraseShutdownControl(operation: value)
        guard !control.installed else { throw AppAccessContractFailureV1.staleAttempt }
        let witness = try value.prepareOriginalShutdownControls(
            registry: control.registry, writer: control.writer, installed: false)
        try control.registry.beginOriginalEraseCheckedShutdown(witness)
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        try control.registry.acquireTemporalNormalizationActivityForOriginalEraseShutdown(
            witness: witness, retainedWriter: control.writer.token,
            retain: { try value.retainOriginalShutdownActivity($0, registry: control.registry) })
        let root = try StoreTemporalPhysicalRootExclusionV1
            .unacquiredOriginalEraseShutdown(at: control.supportURL)
        try value.retainOriginalShutdownRoot(root)
        try root.acquireOriginalEraseShutdown()
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        try control.registry.requireCompletedAbortNoEffectUnderOriginalShutdown(
            witness: witness, service: held.service,
            operation: value, receipt: receipt, coordinator: coordinator)
        try value.markOriginalShutdownControlsTransferred()
        completedAbortFinal = (value, held.service, receipt)
        completedAbortShutdown = nil
        operationOwnedWriter = nil
        pendingErasedActivation = nil
        deferredEraseCoordinator = nil
        maintenanceEraseSession = nil
        maintenanceRestoreSession = nil
        publishedWriter = nil
        preparedStartup = nil
        route = .maintenance(.eraseInconsistent)
    }

    func finishCompletedAbortColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard abandonedOriginalEraseForColdRestart,
              let final = completedAbortFinal,
              final.operation === value,
              final.receipt.matchesExactOriginalAuthority(receipt),
              case .maintenance(.eraseInconsistent) = route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try value.finishCompletedAbortForColdRestart(
            service: final.service, receipt: receipt)
        completedAbortFinal = nil
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
        if durableRetiredFault && expectedFault == .afterSessionPhaseWrite {
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

    private func beginOriginalPreparingEraseColdRestartForTesting(
        _ value: EraseRouterOperationV1,
        originalService: EraseAllService,
        expectedFault: EraseAllFailurePoint?
    ) async throws {
        try requireEraseRetirementOperation(value)
        let durableRetiredFault: Bool
        switch expectedFault {
        case .afterPreparedWrite?, .afterPointerSwitch?,
             .afterPointerPhaseWrite?, .afterSessionPhaseWrite?:
            durableRetiredFault = true
        default:
            durableRetiredFault = false
        }
        if let expectedFault {
            if durableRetiredFault {
                _ = try originalService.interruptedRetiredAuthorityIntentForTesting(
                    expectedFault, operation: value)
            } else {
                try originalService.requireInterruptedOriginalPreparationFaultForTesting(
                    expectedFault, operation: value)
            }
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
        try requireInterruptedDurableEraseRouteForTesting(
            operationID: ticket.operationID, coordinator: coordinator,
            targetGenerationID: subject.newGenerationID,
            expectedFault: expectedFault,
            durableRetiredFault: durableRetiredFault)
        if expectedFault == nil {
            guard notificationRefusalColdExitForTesting == nil else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            try originalService
                .requireOriginalNotificationReadbackRefusalForColdExitForTesting(
                    operation: value, subject: subject)
        }
        if durableRetiredFault, let expectedFault {
            try value.poisonInterruptedDurableOriginalPreparation(
                sourceGenerationID: state.sourceGenerationID,
                targetGenerationID: subject.newGenerationID,
                expectedFault: expectedFault)
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
        let drainID = try coordinator.closeProducerAdmissionForOriginalEraseShutdown()
        coordinator.workspaceWriter.invalidate()
        try await coordinator.awaitProducersForOriginalEraseShutdown(drainID)
        guard abandonedOriginalEraseForColdRestart,
              retainedEraseRetirementOperation === value else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try requireInterruptedDurableEraseRouteForTesting(
            operationID: ticket.operationID, coordinator: coordinator,
            targetGenerationID: subject.newGenerationID,
            expectedFault: expectedFault,
            durableRetiredFault: durableRetiredFault)
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        let control = try coordinator.captureOriginalEraseShutdownControl(operation: value)
        let witness = try value.prepareOriginalShutdownControls(
            registry: control.registry, writer: control.writer,
            installed: control.installed)
        // Selective fence and EX acquisition are synchronous with no await.
        try control.registry.beginOriginalEraseCheckedShutdown(witness)
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        try control.registry.acquireTemporalNormalizationActivityForOriginalEraseShutdown(
            witness: witness, retainedWriter: control.writer.token,
            retain: { try value.retainOriginalShutdownActivity($0, registry: control.registry) })
        let root = try StoreTemporalPhysicalRootExclusionV1
            .unacquiredOriginalEraseShutdown(at: control.supportURL)
        try value.retainOriginalShutdownRoot(root)
        try root.acquireOriginalEraseShutdown()
        try coordinator.requireOriginalEraseShutdownProducerDrain(drainID)
        coordinator.workspaceWriter.invalidate()
        // If another genuine activation route retained the target strongly,
        // reprove its exact identity before transferring that aggregate.
        try requireInterruptedDurableEraseRouteForTesting(
            operationID: ticket.operationID, coordinator: coordinator,
            targetGenerationID: subject.newGenerationID,
            expectedFault: expectedFault,
            durableRetiredFault: durableRetiredFault)
        try value.markOriginalShutdownControlsTransferred()
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
              let subject = state.eraseSubject,
              let reservation = state.acknowledgedReservation,
              reservation.subject == subject,
              case let .eraseCleanupPending(.preparing(coordinator)) = route,
              state.source.coordinator === coordinator,
              retainedEraseRetirementOperation === value,
              !value.detached else {
            throw AppAccessContractFailureV1.staleAttempt
        }
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
        try requireErasePreparationTarget(operation, session: session, coordinator: coordinator)
        guard pendingWriterLeaseReleases.isEmpty, pendingCoordinatorReleases.isEmpty,
              preparedStartup == nil, publishedWriter == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let capturedFactory = try generationFactory.capturingEraseReaders(in: operation.inventory)
        let ordinaryFactory = try capturedFactory.ordinaryViewForErasePreparation(
            operation: operation, session: session, coordinator: coordinator)
        try coordinator.activateForErasePreparation(session: session,
            generationFactory: ordinaryFactory, operation: operation)
        let owner = OwnedWriter(coordinator)
        operationOwnedWriter = owner
        pendingErasedActivation = (owner, session, operation.ticket.operationID)
        deferredEraseCoordinator = nil
        route = .checking
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

    fileprivate func requireNoWork() throws {
        guard !serviceFrame, !advancingCleanup, prepared == nil, rollback == nil,
              !retirementAcquisitionStarted else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        if !cold.hasPreparedCleanup && !cold.hasRollback {
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
            coldErasePreparation = nil
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

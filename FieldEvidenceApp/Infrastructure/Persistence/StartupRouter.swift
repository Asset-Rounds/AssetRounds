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
        case eraseCleanupPending(StoreSessionCoordinator)
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
    fileprivate final class OriginalOperationMint: @unchecked Sendable {}
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
        var eraseSubject: EraseAllOperationSubjectV1?
        var eraseAuthorizationIssued = false
        var acknowledgedReservation: AppAccessGateV1.EraseAdoptionToken?
        var postAdoptionStartup = false
        var postAdoptionExecutionID: UUID?
    }
    private let originalOperationOwner = OriginalOperationOwner()
    private var originalOperations: [UUID: OriginalOperationState] = [:]
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
    private enum StartupAuthorization {
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
    }
    private var startupAccessGate: AppAccessGateV1?
    private var operationAuthorization: StartupAuthorization?
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
              originalOperations.isEmpty else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        let authorization = try await startupAuthorization(accessGate)
        guard pendingEraseDrainProof == nil, !isRunning,
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
              originalOperations.isEmpty, resolvePendingWriterCleanup(),
              publishedWriter.map({ $0.coordinator === coordinator &&
                  $0.writer === coordinator.workspaceWriter }) ?? true else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        let authorization = try await startupAuthorization(accessGate)
        guard !isRunning, pendingEraseDrainProof == nil,
              originalOperations.isEmpty, resolvePendingWriterCleanup(),
              publishedWriter.map({ $0.coordinator === coordinator &&
                  $0.writer === coordinator.workspaceWriter }) ?? true else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let operation = beginOperation(.erase, authorization: authorization)
        operationOwnedWriter = publishedWriter
        publishedWriter = nil
        pendingEraseDrainProof = EraseGenerationDrainProof(
            priorContext: coordinator.modelContext
        )
        let mint = OriginalOperationMint()
        originalOperations[operation] = OriginalOperationState(
            kind: .erase, owner: originalOperationOwner, mint: mint,
            sourceGenerationID: coordinator.generationID,
            source: OriginalOperationSourceReference(
                coordinator: coordinator, modelContext: coordinator.modelContext
            ), authorization: authorization
        )
        maintenanceRestoreSession = nil
        maintenanceEraseSession = nil
        route = .checking
        return OriginalOperationTicket(owner: originalOperationOwner, mint: mint,
                                       operationID: operation)
    }

    /// Returns the original permit once.  It does not reserve at the gate:
    /// the lifecycle owns that atomic reservation and exact-subject resume.
    func eraseAdmissionAuthorization(
        _ ticket: OriginalOperationTicket,
        subject: EraseAllOperationSubjectV1
    ) async throws -> AppAccessGateV1.ContentReadToken? {
        var state = try await validateOriginalOperation(ticket, kind: .erase)
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
              operationID == ticket.operationID || operationID == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
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

    private func runStartup(authorization: StartupAuthorization?) async {
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
        guard resolvePendingWriterCleanup() else {
            enterWriterCleanupMaintenance(.dataPointerInvalid)
            return
        }
        if let startupPreparationFailure {
            route = .maintenance(startupPreparationFailure)
            return
        }
        if let pendingEraseDrainProof {
            if originalOperations.values.contains(where: { $0.kind == .erase }) {
                if let deferredEraseCoordinator {
                    route = .eraseCleanupPending(deferredEraseCoordinator)
                } else {
                    route = .maintenance(.eraseInconsistent)
                }
                return
            }
            guard pendingEraseDrainProof.isDrained else {
                if let deferredEraseCoordinator {
                    route = .eraseCleanupPending(deferredEraseCoordinator)
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
            } else if let erasedSession {
                session = erasedSession
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
            let coordinator = try StoreSessionCoordinator(
                validatingSession: session,
                lifecycleProfileRegistry: lifecycleProfileRegistry
            )
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
            route = deferredEraseCoordinator.map(Route.eraseCleanupPending) ?? .checking
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
                guard ownsActivatedWriter,
                      self.pendingEraseDrainProof?.isDrained == true,
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
        route = .eraseCleanupPending(coordinator)
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
        guard let retirement = eraseCleanupRetirement,
              retirement.operationID == ticket.operationID,
              (try? awaitlessValidateEraseTicket(ticket)) != nil else { return }
        deferredEraseCoordinator = retirement.owner.coordinator
        pendingErasedActivation = nil
        publishedWriter = nil
        endOperation(ticket.operationID)
        route = .eraseCleanupPending(retirement.owner.coordinator)
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
                                       owner: OwnedWriter) throws -> StartupMediaOwnershipSnapshotV1 {
        guard !session.modelContext.hasChanges else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        let revision = try owner.writer.currentRevision()
        let authorities = try session.modelContext.fetch(FetchDescriptor<EvidenceFile>()).map {
            EvidenceBundleAuthority(schemaVersion: $0.schemaVersion, id: $0.id, recordID: $0.recordID,
                purposeKey: $0.purposeKey, relativePath: $0.relativePath, mimeType: $0.mimeType,
                byteCount: $0.byteCount, sha256: $0.sha256, thumbnailRelativePath: $0.thumbnailRelativePath,
                thumbnailByteCount: $0.thumbnailByteCount, thumbnailSHA256: $0.thumbnailSHA256)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let checkpoints = try session.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
            .map { try $0.value() }.filter { $0.codec.codecID == CheckRunnerPhotoDraftCodecV1.codecID }
            .sorted { $0.draftID.uuidString < $1.draftID.uuidString }
        var photos: [StartupMediaPhotoOwnershipV1] = []
        for checkpoint in checkpoints {
            let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
            guard checkpoint.workspaceID == session.workspaceID else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let targetCommitted: Bool
            if checkpoint.state == .committed {
                guard let current = try owner.writer.checkRunnerPhotoCurrentTargetEvidence(
                    workspaceID: session.workspaceID, parentDraftID: payload.parentDraftID,
                    childDraftID: checkpoint.draftID),
                      case let .applyCommitTerminal(bundle, _) = current.parent.child.terminal.mutation.postImage,
                      bundle.committedCheckpoint == checkpoint else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
                targetCommitted = true
            } else {
                switch payload.phase {
                case .awaitingRawStage, .rawReady:
                    guard let current = try owner.writer.checkRunnerPhotoRawStageEvidence(
                        workspaceID: session.workspaceID, parentDraftID: payload.parentDraftID,
                        childDraftID: checkpoint.draftID), current.currentCheckpoint == checkpoint else {
                        throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                    }
                    targetCommitted = false
                case .pairReady, .preparedCommit:
                    guard let current = try owner.writer.checkRunnerPhotoContinuationEvidence(
                        workspaceID: session.workspaceID, parentDraftID: payload.parentDraftID,
                        childDraftID: checkpoint.draftID), current.checkpoint == checkpoint else {
                        throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                    }
                    targetCommitted = current.target != nil
                }
            }
            photos.append(.init(checkpoint: checkpoint, payload: payload, targetCommitted: targetCommitted))
        }
        guard !session.modelContext.hasChanges, try owner.writer.currentRevision() == revision else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return .init(revision: revision, authorities: authorities, photos: photos)
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
        try await requireCurrentOperationAndAccess(operation, owner: owner)
        let originalAuthorization = operationAuthorization
        let snapshot = try currentMediaOwnership(session: session, owner: owner)
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        let authority = StartupMediaRecoveryAuthorityV1(snapshot: snapshot) {
            try self.requireCurrentOperation(operation, owner: owner)
            guard try self.currentMediaOwnership(session: session, owner: owner) == snapshot else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
        let store = EvidenceBundleStore(generationRootURL: session.generationRootURL, fileManager: fileManager)
        let prepared = try await store.prepareStartupRecovery(authority: authority,
            expectedGenerationRootIdentity: rootIdentity)
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

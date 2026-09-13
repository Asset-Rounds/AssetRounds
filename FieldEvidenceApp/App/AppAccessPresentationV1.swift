import Combine
import Foundation
import SwiftData

/// Reason-bearing presentation failures. These are intentionally coarse: the
/// access contracts retain the detailed error, while UI must never render it.
enum AppAccessPresentationFailureV1: Equatable {
    case bootstrap
    case authentication(LocalAuthenticationOutcomeV1)
    case configuration
    case startup
    case lifecycle(AppLockLifecycleEventV1)
}

/// The one app-facing owner for the pre-authentication access composition.
/// It raises the privacy cover synchronously, while its actor work remains
/// serialized behind the existing lifecycle and startup authorities.
@MainActor
final class AppAccessPresentationV1: ObservableObject {
    typealias SessionFactory = @MainActor () async throws -> ProductionAppAccessSessionV1
    typealias EraseAdmission = @MainActor (EraseAllOperationSubjectV1) async throws -> AppAccessGateV1.EraseAdoptionToken
    typealias EraseCompletion = @MainActor (CompletedEraseReceiptV1) -> Void
    typealias EraseAbort = @MainActor (AbortedEraseAdmissionReceiptV1) -> Void
    typealias EraseServiceFactory = @MainActor (EraseAdmission?, EraseCompletion?, EraseAbort?, any SceneNavigationDeviceStatePortV1) -> EraseAllService
    typealias RestoreServiceFactory = @MainActor (URL) throws -> BackupRestoreService

    @Published private(set) var permitsContentPresentation = false
    @Published private(set) var isBusy = false
    @Published private(set) var settingIsEnabled: Bool?
    @Published private(set) var accessState: AppAccessStateV1?
    @Published private(set) var failure: AppAccessPresentationFailureV1?

    /// Captured by one presented Restore destination. A later foreground
    /// publication cannot authorize a callback retained by the older view.
    struct ContentAccess {
        private let token: AppAccessGateV1.ContentReadToken
        private let surface: AppAccessContentReadSurfaceV1
        private let gate: AppAccessGateV1
        private let isCurrent: @MainActor () -> Bool

        fileprivate init(token: AppAccessGateV1.ContentReadToken,
                         surface: AppAccessContentReadSurfaceV1,
                         gate: AppAccessGateV1,
                         isCurrent: @escaping @MainActor () -> Bool) {
            self.token = token
            self.surface = surface
            self.gate = gate
            self.isCurrent = isCurrent
        }

        @MainActor
        func isBound(to expectedGate: AppAccessGateV1) -> Bool { gate === expectedGate }

        @MainActor
        func withRead<T>(_ body: () throws -> T) throws -> T {
            guard isCurrent() else { throw AppAccessContractFailureV1.accessDenied }
            return try token.withContentRead(for: surface, body)
        }
    }
    typealias BackupPreviewAccess = ContentAccess

    /// My Day reads and planning actions bound to one visible content publication.
    /// The provider retains its own gate/session/writer/source validation; the
    /// surrounding access additionally rejects a presentation replaced while
    /// its asynchronous snapshot was materializing.
    @MainActor
    struct MyDayAccess {
        private let publicationAccess: ContentAccess
        private let provider: ProductionMyDaySourceProviderV1
        private let planning: ProductionMyDayPlanningCommitServiceV1

        fileprivate init(publicationAccess: ContentAccess,
                         provider: ProductionMyDaySourceProviderV1,
                         planning: ProductionMyDayPlanningCommitServiceV1) {
            self.publicationAccess = publicationAccess
            self.provider = provider
            self.planning = planning
        }

        func captureConfirmedPlanningContext(for key: MyDayKeyV1,
                                             recordedByName: String) throws -> MyDayPlanningConfirmedContextV1 {
            try planning.captureConfirmedPlanningContext(for: key, recordedByName: recordedByName,
                                                         authorizing: publicationAccess)
        }

        func nextPlanningMembershipID() throws -> UUID {
            try planning.nextPlanningMembershipID(authorizing: publicationAccess)
        }

        func planningCheckpoints(for key: MyDayKeyV1) throws -> [FieldDraftCheckpointV1] {
            try planning.planningCheckpoints(for: key, authorizing: publicationAccess)
        }

        func planningContext(for key: MyDayKeyV1) throws -> MyDayPlanningContextSnapshotV1 {
            try planning.planningContext(for: key, authorizing: publicationAccess)
        }

        func prepareEditingWrite(_ request: MyDayPlanningPlanSaveRequestV1,
                                 replacing previous: FieldDraftCheckpointV1?,
                                 resumeAnchor: DraftResumeAnchorV1) throws -> MyDayPlanningEditingWriteV1 {
            try planning.prepareEditingWrite(request, replacing: previous,
                resumeAnchor: resumeAnchor, authorizing: publicationAccess)
        }

        func prepareCarryoverEditingWrite(_ request: MyDayPlanningCarryoverRequestV1,
                                         replacing previous: FieldDraftCheckpointV1?,
                                         resumeAnchor: DraftResumeAnchorV1) throws -> MyDayPlanningEditingWriteV1 {
            try planning.prepareCarryoverEditingWrite(request, replacing: previous,
                resumeAnchor: resumeAnchor, authorizing: publicationAccess)
        }

        func preparePlanningEditingWrite<Request: MyDayPlanningEditingRequestV1>(_ request: Request,
                                         replacing previous: FieldDraftCheckpointV1?,
                                         resumeAnchor: DraftResumeAnchorV1) throws -> MyDayPlanningEditingWriteV1 {
            try planning.preparePlanningEditingWrite(request, replacing: previous,
                resumeAnchor: resumeAnchor, authorizing: publicationAccess)
        }

        func persistEditingWrite(_ write: MyDayPlanningEditingWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.persistEditingWrite(write, authorizing: publicationAccess)
        }

        func preparePlanningDiscard(expectedCheckpoint: FieldDraftCheckpointV1) throws -> MyDayPlanningDiscardWriteV1 {
            try planning.preparePlanningDiscard(expectedCheckpoint: expectedCheckpoint, authorizing: publicationAccess)
        }

        func discardPlanningDraft(_ write: MyDayPlanningDiscardWriteV1) async throws -> MyDayPlanningDiscardOutcomeV1 {
            try await planning.discardPlanningDraft(write, authorizing: publicationAccess)
        }

        func discardedPlanningAcknowledgement(expectedCheckpoint: FieldDraftCheckpointV1) throws -> MyDayPlanningDiscardOutcomeV1 {
            try planning.discardedPlanningAcknowledgement(expectedCheckpoint: expectedCheckpoint, authorizing: publicationAccess)
        }

        func prepareStalePlanPredecessorConflict(draftID: UUID) throws -> MyDayPlanningConflictClassificationWriteV1 {
            try planning.prepareStalePlanPredecessorConflict(draftID: draftID, authorizing: publicationAccess)
        }

        func executeStalePlanPredecessorConflict(_ write: MyDayPlanningConflictClassificationWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.executeStalePlanPredecessorConflict(write, authorizing: publicationAccess)
        }

        func retryStalePlanPredecessorConflict(_ write: MyDayPlanningConflictClassificationWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.retryStalePlanPredecessorConflict(write, authorizing: publicationAccess)
        }


        func planningConflictReview(draftID: UUID) throws -> MyDayPlanningConflictReviewV1 {
            try planning.planningConflictReview(draftID: draftID, authorizing: publicationAccess)
        }

        func prepareStaleCarryoverTargetConflict(draftID: UUID) throws -> MyDayPlanningCarryoverConflictClassificationWriteV1 {
            try planning.prepareStaleCarryoverTargetConflict(draftID: draftID, authorizing: publicationAccess)
        }

        func executeStaleCarryoverTargetConflict(_ write: MyDayPlanningCarryoverConflictClassificationWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.executeStaleCarryoverTargetConflict(write, authorizing: publicationAccess)
        }

        func retryStaleCarryoverTargetConflict(_ write: MyDayPlanningCarryoverConflictClassificationWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.retryStaleCarryoverTargetConflict(write, authorizing: publicationAccess)
        }


        func carryoverConflictReview(draftID: UUID) throws -> MyDayPlanningCarryoverConflictReviewV1 {
            try planning.carryoverConflictReview(draftID: draftID, authorizing: publicationAccess)
        }

        func prepareReviewedCarryoverRebase(_ review: MyDayPlanningCarryoverConflictReviewV1) throws -> MyDayPlanningReviewedCarryoverResolutionWriteV1 {
            try planning.prepareReviewedCarryoverRebase(review, authorizing: publicationAccess)
        }

        func executeReviewedCarryoverRebase(_ write: MyDayPlanningReviewedCarryoverResolutionWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.executeReviewedCarryoverRebase(write, authorizing: publicationAccess)
        }

        func retryReviewedCarryoverRebase(_ write: MyDayPlanningReviewedCarryoverResolutionWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.retryReviewedCarryoverRebase(write, authorizing: publicationAccess)
        }

        func prepareReviewedPlanRebase(_ review: MyDayPlanningConflictReviewV1,
                                       editedDraft: MyDayPlanDraftV1) throws -> MyDayPlanningReviewedResolutionWriteV1 {
            try planning.prepareReviewedPlanRebase(review, editedDraft: editedDraft,
                authorizing: publicationAccess)
        }

        func executeReviewedPlanRebase(_ write: MyDayPlanningReviewedResolutionWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.executeReviewedPlanRebase(write, authorizing: publicationAccess)
        }

        func retryReviewedPlanRebase(_ write: MyDayPlanningReviewedResolutionWriteV1) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.retryReviewedPlanRebase(write, authorizing: publicationAccess)
        }


        func loadPlanningCheckpoint(draftID: UUID) throws -> FieldDraftCheckpointV1 {
            try planning.loadPlanningCheckpoint(draftID: draftID, authorizing: publicationAccess)
        }

        func editingAcknowledgement(draftID: UUID) throws -> MyDayPlanningCheckpointAcknowledgementV1 {
            try planning.editingAcknowledgement(draftID: draftID, authorizing: publicationAccess)
        }

        func savePlan(_ request: MyDayPlanningPlanSaveRequestV1) async throws -> MyDayPlanningCommitOutcomeV1 {
            try await planning.savePlan(request, authorizing: publicationAccess)
        }

        func retryPlanSave(draftID: UUID) async throws -> MyDayPlanningCommitOutcomeV1 {
            try await planning.retryPlanSave(draftID: draftID, authorizing: publicationAccess)
        }

        func saveCarryover(_ request: MyDayPlanningCarryoverRequestV1) async throws -> MyDayPlanningCommitOutcomeV1 {
            try await planning.saveCarryover(request, authorizing: publicationAccess)
        }

        func retryPlanningCommit(draftID: UUID) async throws -> MyDayPlanningCommitOutcomeV1 {
            try await planning.retryPlanningCommit(draftID: draftID, authorizing: publicationAccess)
        }

        func snapshot(for plan: MyDayPlanV1? = nil,
                      evaluatedAt: Date) async throws -> MyDaySourceSnapshotV1 {
            try publicationAccess.withRead {}
            let result = try await provider.snapshot(for: plan, evaluatedAt: evaluatedAt)
            try publicationAccess.withRead {}
            return result
        }

        /// Keep the original publication authorized through a synchronous UI
        /// state assignment after the asynchronous source read has returned.
        func withCurrentPresentation<T>(_ body: () throws -> T) throws -> T {
            try publicationAccess.withRead(body)
        }

        #if DEBUG
        func setPlanningEffectHookForTesting(
            _ hook: (@MainActor (MyDayPlanningEffectPointV1) throws -> Void)?
        ) { planning.afterEffectForTesting = hook }

        func setPlanningPromotionHookForTesting(
            _ hook: (@MainActor @Sendable () async throws -> Void)?
        ) { planning.afterZeroStagePromotionForTesting = hook }

        func setPlanningDiscardHookForTesting(
            _ hook: (@MainActor @Sendable () async throws -> Void)?
        ) { planning.afterZeroStageDiscardForTesting = hook }

        /// Fault injection only. It cannot replace source data or authority.
        func setAfterSourceMaterializationForTesting(
            _ hook: (@MainActor () async throws -> Void)?
        ) {
            provider.afterSourceMaterializationForTesting = hook
        }
        #endif
    }

    /// Captures only device state and value identities, never a store context
    /// that could keep the old generation alive during Erase.
    @MainActor
    struct SceneNavigationAccess {
        private let token: AppAccessGateV1.ContentReadToken
        private let isCurrent: @MainActor () -> Bool
        private let adapter: SceneNavigationStateAdapterV1
        private let router: StartupRouter
        private let workspaceID: WorkspaceID
        private let generationID: UUID

        fileprivate init(token: AppAccessGateV1.ContentReadToken,
                         isCurrent: @escaping @MainActor () -> Bool,
                         port: any SceneNavigationDeviceStatePortV1,
                         router: StartupRouter, workspaceID: WorkspaceID, generationID: UUID) {
            self.token = token
            self.isCurrent = isCurrent
            adapter = SceneNavigationStateAdapterV1(port: port)
            self.router = router
            self.workspaceID = workspaceID
            self.generationID = generationID
        }

        func load() throws -> SceneNavigationLoadResultV1 {
            guard isCurrent() else { throw AppAccessContractFailureV1.accessDenied }
            return try adapter.loadAndReconcile(using: token)
        }

        func save(_ snapshot: SceneNavigationSnapshotV1) throws {
            guard isCurrent() else { throw AppAccessContractFailureV1.accessDenied }
            guard snapshot.workspaceID == workspaceID else { throw SceneNavigationFailureV1.invalidSnapshot }
            try adapter.save(snapshot, using: token)
        }

        func restore(_ request: RouteRestorationRequestV1,
                     using coordinator: RouteCoordinatorV1) throws -> SceneNavigationRestorationResultV1 {
            guard isCurrent() else { throw AppAccessContractFailureV1.accessDenied }
            return try router.restoreSceneNavigationState(request, using: coordinator,
                workspaceID: workspaceID, generationID: generationID, authorization: token)
        }

        func restore(loaded: SceneNavigationLoadResultV1,
                     explicitIngressTarget: NavigationTargetV1? = nil,
                     using coordinator: RouteCoordinatorV1,
                     evidenceKind: RouteEvidenceKindV1,
                     receiptID: UUID = UUID()) throws -> SceneNavigationRestorationResultV1 {
            guard isCurrent() else { throw AppAccessContractFailureV1.accessDenied }
            return try router.restoreSceneNavigationState(loaded: loaded,
                explicitIngressTarget: explicitIngressTarget, using: coordinator,
                workspaceID: workspaceID, generationID: generationID, authorization: token,
                evidenceKind: evidenceKind, receiptID: receiptID)
        }
    }

    private var publishedBackupPreviewAccess: BackupPreviewAccess?
    private var publishedRenderAccess: ContentAccess?
    private var publishedSceneNavigationAccess: SceneNavigationAccess?
    private var publishedMyDayAccess: MyDayAccess?
    private final class ContentPublication {}
    private var contentPublication: ContentPublication?
    var backupPreviewAccess: BackupPreviewAccess? {
        permitsContentPresentation ? publishedBackupPreviewAccess : nil
    }
    var renderAccess: ContentAccess? {
        permitsContentPresentation ? publishedRenderAccess : nil
    }
    var sceneNavigationAccess: SceneNavigationAccess? {
        permitsContentPresentation ? publishedSceneNavigationAccess : nil
    }
    var myDayAccess: MyDayAccess? {
        permitsContentPresentation ? publishedMyDayAccess : nil
    }

    private struct QueuedLifecycleEvent {
        let event: AppLockLifecycleEventV1
    }

    private final class HardEpoch {}
    private final class PresentationRevision {}
    private final class Action {
        let hardEpoch: HardEpoch
        let revision: PresentationRevision
        let resumesAfterInactive: Bool

        init(hardEpoch: HardEpoch, revision: PresentationRevision,
             resumesAfterInactive: Bool) {
            self.hardEpoch = hardEpoch
            self.revision = revision
            self.resumesAfterInactive = resumesAfterInactive
        }
    }
    private struct PendingAuthorizedStartup {
        let session: ProductionAppAccessSessionV1
        let hardEpoch: HardEpoch
        let resumesAfterInactive: Bool
    }

    /// Physical cleanup ownership survives a presentation/background epoch.
    /// Its service hooks and receipt always belong to this original ticket.
    private final class PendingErase {
        let ticket: StartupRouter.OriginalOperationTicket
        let coordinator: StoreSessionCoordinator
        let diagnostics: DiagnosticsStore
        var makeRecoveryService: (@MainActor () -> EraseAllService)?
        var session: StoreGenerationSession?
        var receipt: CompletedEraseReceiptV1?
        var abortedAdmission: AbortedEraseAdmissionReceiptV1?
        var reservation: AppAccessGateV1.EraseAdoptionToken?
        var adopted = false
        var activationFailure: Error?

        init(ticket: StartupRouter.OriginalOperationTicket,
             coordinator: StoreSessionCoordinator, diagnostics: DiagnosticsStore) {
            self.ticket = ticket
            self.coordinator = coordinator
            self.diagnostics = diagnostics
        }
    }

    private let startupRouter: StartupRouter
    private let sessionFactory: SessionFactory
    private let eraseServiceFactory: EraseServiceFactory?
    private let restoreServiceFactory: RestoreServiceFactory
    private var session: ProductionAppAccessSessionV1?
    private var bootstrapTask: Task<Void, Never>?
    private var lifecycleDrainTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var queuedLifecycleEvents: [QueuedLifecycleEvent] = []
    private var sceneIsActive = true
    private var presentationRevision = PresentationRevision()
    // Only hard revocation changes this generation. Inactive is deliberately
    // a cover/presentation transition, so an in-flight system authentication
    // can settle normally.
    private var hardEpoch = HardEpoch()
    private var activeAction: Action?
    private var pendingAuthorizedStartup: PendingAuthorizedStartup?
    private var pendingErase: PendingErase?

    init(
        startupRouter: StartupRouter,
        applicationSupportURL: URL,
        defaults: UserDefaults = .standard
    ) {
        self.startupRouter = startupRouter
        restoreServiceFactory = { try BackupRestoreService(applicationSupportURL: $0) }
        eraseServiceFactory = { admission, completion, aborted, sceneState in
            EraseAllService(applicationSupportURL: applicationSupportURL,
                userDefaults: defaults, sceneNavigationStatePort: sceneState,
                admitErase: admission, didCompleteErase: completion,
                didAbortEraseAdmission: aborted)
        }
        sessionFactory = {
            try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: applicationSupportURL,
                startupRouter: startupRouter,
                defaults: defaults
            )
        }
    }

    init(startupRouter: StartupRouter, eraseServiceFactory: EraseServiceFactory? = nil,
         restoreServiceFactory: @escaping RestoreServiceFactory = { try BackupRestoreService(applicationSupportURL: $0) },
         sessionFactory: @escaping SessionFactory) {
        self.startupRouter = startupRouter
        self.eraseServiceFactory = eraseServiceFactory
        self.restoreServiceFactory = restoreServiceFactory
        self.sessionFactory = sessionFactory
    }

    func bootstrapIfNeeded() async {
        if session != nil {
            scheduleLifecycleDrain()
            return
        }
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performBootstrap()
        }
        bootstrapTask = task
        await task.value
    }

    /// Covers synchronously and queues the actor transition. Callers use this
    /// from scene callbacks; it never waits on authentication or recovery.
    func receive(_ event: AppLockLifecycleEventV1) {
        presentationRevision = PresentationRevision()
        publishedMyDayAccess = nil
        switch event {
        case .sceneInactive:
            sceneIsActive = false
            permitsContentPresentation = false
            startupRouter.pauseForAppAccess(discardPrepared: false)
        case .sceneActive:
            sceneIsActive = true
        case .sceneBackground, .protectedDataUnavailable, .termination:
            sceneIsActive = false
            invalidateForHardRevocation()
            permitsContentPresentation = false
            startupRouter.pauseForAppAccess(discardPrepared: true)
        case .coldLaunch, .lockNow, .erase:
            invalidateForHardRevocation()
            permitsContentPresentation = false
            startupRouter.pauseForAppAccess(discardPrepared: true)
        }
        queuedLifecycleEvents.append(.init(event: event))
        scheduleLifecycleDrain()
    }

    func unlock() async {
        await bootstrapIfNeeded()
        guard let session else { return }
        guard sceneIsActive else {
            failure = .authentication(.interrupted)
            return
        }
        guard let action = beginLongAction(resumesAfterInactive: true) else { return }
        defer { finishLongAction(action) }
        failure = nil

        let state = await session.gate.currentState()
        if state == .configurationUnknownLocked {
            do {
                // The lifecycle owns repair authentication when a durable
                // journal requires it. Calling the gate first would evaluate
                // Local Authentication twice and lose the one owned proof.
                _ = try await session.lifecycle.recoverAfterAuthentication()
                _ = try await refreshState(session, action: action)
            } catch {
                if isCurrent(action) { failure = .configuration }
            }
            return
        }

        let outcome = await session.gate.authenticate(trigger: .unlock)
        guard isCurrent(action), outcome == .authenticated else {
            if isCurrent(action) { failure = .authentication(outcome) }
            return
        }
        if sceneIsActive {
            await startAndPublish(session, action: action)
        } else if isCurrent(action) {
            retainPendingStartup(session, action: action)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        await bootstrapIfNeeded()
        guard let session, sceneIsActive else { return }
        guard let action = beginLongAction(resumesAfterInactive: false) else { return }
        defer { finishLongAction(action) }
        failure = nil
        do {
            if enabled {
                _ = try await session.lifecycle.enable(operationID: UUID())
                // Configuration enable is deliberately locked; it never
                // manufactures a content presentation permit.
                permitsContentPresentation = false
                publishedMyDayAccess = nil
            } else {
                _ = try await session.lifecycle.disable(operationID: UUID())
            }
            _ = try await refreshState(session, action: action)
            if !enabled, isCurrent(action), sceneIsActive {
                await startAndPublish(session, action: action)
            }
        } catch {
            if isCurrent(action) { failure = .configuration }
        }
    }

    func lockNow() {
        receive(.lockNow)
    }

    func retryStartup() async {
        await bootstrapIfNeeded()
        guard let session, sceneIsActive else { return }
        if let pendingErase {
            guard let action = beginLongAction(resumesAfterInactive: true) else { return }
            defer { finishLongAction(action) }
            do {
                try await resumeErase(pendingErase, access: session)
                if isCurrent(action), self.pendingErase == nil {
                    failure = nil
                    await startAndPublish(session, action: action)
                }
            } catch {
                permitsContentPresentation = false
                publishedMyDayAccess = nil
                failure = .startup
            }
            return
        }
        let state = await session.gate.currentState()
        guard state.permitsContentAccess else {
            failure = .startup
            return
        }
        guard let action = beginLongAction(resumesAfterInactive: true) else { return }
        defer { finishLongAction(action) }
        failure = nil
        await startAndPublish(session, action: action, retriesStartup: true)
    }

    func performRestore(
        applicationSupportURL: URL,
        package: ValidatedV4BackupPackageV1,
        sourceModelContext: ModelContext,
        sourceGenerationID: UUID,
        sourceGenerationRootURL: URL,
        mode: BackupRestoreMode,
        coordinator: StoreSessionCoordinator?
    ) async throws {
        await bootstrapIfNeeded()
        guard let session, sceneIsActive, pendingErase == nil,
              let action = beginLongAction(resumesAfterInactive: false) else {
            throw AppAccessContractFailureV1.accessDenied
        }
        defer { finishLongAction(action) }
        let ticket = try await startupRouter.beginRestoreOperation(
            sourceModelContext: sourceModelContext, sourceGenerationID: sourceGenerationID,
            coordinator: coordinator, accessGate: session.gate)
        do {
            guard isCurrent(action), sceneIsActive else {
                throw AppAccessContractFailureV1.accessDenied
            }
            permitsContentPresentation = false
            publishedMyDayAccess = nil
            let restored = try await restoreServiceFactory(applicationSupportURL)
                .restore(validatedPackage: package, currentModelContext: sourceModelContext,
                    currentGenerationID: sourceGenerationID,
                    currentGenerationRootURL: sourceGenerationRootURL, mode: mode,
                    validateAccess: { try await self.startupRouter.validateRestoreOperation(ticket) })
            try await startupRouter.activateRestoredSession(restored, coordinator: coordinator, ticket: ticket)
            if isCurrent(action), sceneIsActive {
                failure = nil
                await startAndPublish(session, action: action)
            }
        } catch {
            startupRouter.failExternalOperation(ticket)
            if isCurrent(action) { failure = .startup }
            throw error
        }
    }

    func performErase(
        applicationSupportURL: URL,
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore
    ) async throws {
        await bootstrapIfNeeded()
        guard let session, sceneIsActive, pendingErase == nil,
              confirmation == EraseAllService.requiredConfirmation,
              let action = beginLongAction(resumesAfterInactive: false) else {
            throw AppAccessContractFailureV1.accessDenied
        }
        defer { finishLongAction(action) }
        let ticket = try await startupRouter.beginEraseOperation(
            coordinator: coordinator, accessGate: session.gate)
        guard isCurrent(action), sceneIsActive else {
            startupRouter.failExternalOperation(ticket)
            throw AppAccessContractFailureV1.accessDenied
        }
        let pending = PendingErase(ticket: ticket, coordinator: coordinator, diagnostics: diagnosticsStore)
        pendingErase = pending
        permitsContentPresentation = false
        publishedMyDayAccess = nil
        failure = nil
        let admission: EraseAdmission = { [weak self, weak pending] subject in
            guard let self, let pending, self.pendingErase === pending else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            let authorization = try await self.startupRouter.eraseAdmissionAuthorization(
                pending.ticket, subject: subject)
            let reservation = try await session.lifecycle.beginExternalErase(subject: subject, authorization: authorization)
            if let original = pending.reservation {
                guard original == reservation else { throw AppAccessContractFailureV1.staleAttempt }
            } else {
                pending.reservation = reservation
                try self.startupRouter.recordEraseReservation(pending.ticket, reservation: reservation)
            }
            return reservation
        }
        let completion: EraseCompletion = { [weak self, weak pending] receipt in
            guard let self, let pending, self.pendingErase === pending else { return }
            // Synchronous and independent of presentation epochs: physical
            // completion is retained even if the scene became inactive.
            if pending.receipt == nil { pending.receipt = receipt }
        }
        let aborted: EraseAbort = { [weak self, weak pending] receipt in
            guard let self, let pending, self.pendingErase === pending else { return }
            if pending.abortedAdmission == nil { pending.abortedAdmission = receipt }
        }
        let factory = eraseServiceFactory
        let sceneState = session.sceneNavigationStatePort()
        let makeService: @MainActor () -> EraseAllService = {
            factory?(admission, completion, aborted, sceneState)
                ?? EraseAllService(applicationSupportURL: applicationSupportURL,
                    sceneNavigationStatePort: sceneState,
                    admitErase: admission, didCompleteErase: completion,
                    didAbortEraseAdmission: aborted)
        }
        pending.makeRecoveryService = makeService
        let service = makeService()
        do {
            let dependencies = try coordinator.packageLifecycleDependencies()
            let outcome = try await service.erase(confirmation: confirmation,
                coordinator: coordinator, diagnosticsStore: diagnosticsStore,
                activate: { [weak self, weak pending] erased in
                    guard let self, let pending, self.pendingErase === pending else { return }
                    pending.session = erased
                    do {
                        try await self.startupRouter.beginErasedSessionActivation(
                            erased, coordinator: coordinator, ticket: pending.ticket)
                    } catch { pending.activationFailure = error }
                }, lifecycleDependencies: dependencies)
            pending.session = outcome.session
            if let activationFailure = pending.activationFailure { throw activationFailure }
            if outcome.cleanupDeferred {
                try startupRouter.deferErasedSessionCleanup(outcome.session,
                    coordinator: coordinator, ticket: ticket)
                failure = .startup
                return
            }
            try await resumeErase(pending, access: session)
            if isCurrent(action), self.pendingErase == nil, sceneIsActive {
                await startAndPublish(session, action: action)
            }
        } catch {
            // Keep the actual cleanup ticket and any authentic receipt for a
            // retry. A retry never starts another physical Erase operation.
            permitsContentPresentation = false
            publishedMyDayAccess = nil
            if let receipt = pending.abortedAdmission {
                do {
                    try await session.lifecycle.abandonEraseAdmission(receipt)
                    try startupRouter.cancelAbortedErase(pending.ticket, receipt: receipt)
                    if pendingErase === pending { pendingErase = nil }
                } catch { /* An unaccepted abort proof remains owned for retry. */ }
            } else if pending.reservation == nil {
                startupRouter.failExternalOperation(ticket)
                if pendingErase === pending { pendingErase = nil }
            }
            _ = try? await refreshState(session)
            failure = pendingErase == nil && accessState?.permitsContentAccess == false ? nil : .startup
            throw error
        }
    }

    private func resumeErase(_ pending: PendingErase, access: ProductionAppAccessSessionV1) async throws {
        guard pendingErase === pending, let makeService = pending.makeRecoveryService else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        if let receipt = pending.abortedAdmission {
            try await access.lifecycle.abandonEraseAdmission(receipt)
            try startupRouter.cancelAbortedErase(pending.ticket, receipt: receipt)
            pendingErase = nil
            _ = try await refreshState(access)
            return
        }
        if pending.receipt == nil {
            // Recovery constructs fresh service-local admission state while
            // reusing the original hooks, subject and lifecycle reservation.
            let service = makeService()
            let recovered = try await startupRouter.resumeDeferredErase(pending.ticket) {
                try await service.reconcileAtStartup(diagnosticsStore: pending.diagnostics)
            }
            if let recovered {
                pending.session = recovered
                try await startupRouter.beginErasedSessionActivation(recovered,
                    coordinator: pending.coordinator, ticket: pending.ticket)
            }
        }
        guard let receipt = pending.receipt, let erasedSession = pending.session else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        if !pending.adopted {
            guard let makeReplacement = access.completedEraseReplacement else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let replacement = try makeReplacement(receipt.subject)
            try await access.lifecycle.adoptCompletedErase(receipt, replacement: replacement)
            pending.adopted = true
        }
        // The router's fresh active startup token controls publication. An
        // inactive/protected-data failure retains adopted completion for retry.
        try await startupRouter.finishErasedSessionActivation(erasedSession,
            coordinator: pending.coordinator, ticket: pending.ticket, accessGate: access.gate)
        guard pendingErase === pending else { throw AppAccessContractFailureV1.staleAttempt }
        pendingErase = nil
        failure = nil
    }

    private func performBootstrap() async {
        defer { bootstrapTask = nil }
        do {
            let bootstrapRevision = presentationRevision
            let composed = try await sessionFactory()
            session = composed
            _ = try await refreshState(composed, expectedRevision: bootstrapRevision)
            failure = nil
            scheduleLifecycleDrain()
        } catch {
            failure = .bootstrap
            permitsContentPresentation = false
            publishedMyDayAccess = nil
        }
    }

    private func scheduleLifecycleDrain() {
        guard session != nil, lifecycleDrainTask == nil else { return }
        lifecycleDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainLifecycleEvents()
        }
    }

    private func drainLifecycleEvents() async {
        guard let session else {
            lifecycleDrainTask = nil
            return
        }
        while !queuedLifecycleEvents.isEmpty {
            let queued = queuedLifecycleEvents.removeFirst()
            let eventRevision = presentationRevision
            do {
                _ = try await session.lifecycle.handle(queued.event)
                _ = try await refreshState(session, expectedRevision: eventRevision)
            } catch {
                // A hard transition already covered content synchronously.
                // For a transient event, retain the cover until a later user
                // action succeeds rather than attempting another operation.
                failure = .lifecycle(queued.event)
                permitsContentPresentation = false
                publishedMyDayAccess = nil
            }
        }
        // Startup can be long-running. Release this serial short-event drain
        // before considering it, so a background edge reaches the gate now.
        lifecycleDrainTask = nil
        scheduleEligibleStartup(session)
    }

    private func startAndPublish(
        _ session: ProductionAppAccessSessionV1,
        action: Action,
        retriesStartup: Bool = false
    ) async {
        publishedMyDayAccess = nil
        do {
            // This concrete token spans the startup awaits and prevents a
            // relock/unlock ABA from publishing an old authorized action.
            let startupToken = try await session.gate.beginContentRead(for: .startupRecovery)
            if retriesStartup {
                // Explicit retry must re-enter the router's recovery checks;
                // startIfNeeded correctly preserves a settled/prepared owner
                // but intentionally skips a router that already started.
                try await startupRouter.retryChecks(accessGate: session.gate)
            } else {
                try await startupRouter.startIfNeeded(accessGate: session.gate)
            }
            let token = try await session.gate.beginContentRead(for: .render)
            let backupToken = try await session.gate.beginContentRead(for: .backupImport)
            let sceneToken = try await session.gate.beginContentRead(for: .sceneRestoration)
            let state = await session.gate.currentState()
            // This is deliberately the final awaited gate call. The token
            // originates before router startup and rejects relock/unlock ABA.
            try await session.gate.validateContentRead(startupToken, for: .startupRecovery)
            try await session.gate.validateContentRead(token, for: .render)
            try await session.gate.validateContentRead(backupToken, for: .backupImport)
            try await session.gate.validateContentRead(sceneToken, for: .sceneRestoration)
            guard isCurrent(action),
                  action.revision === presentationRevision,
                  sceneIsActive,
                  queuedLifecycleEvents.isEmpty,
                  state.permitsContentAccess else {
                if isCurrent(action), action.resumesAfterInactive {
                    retainPendingStartup(session, action: action)
                }
                return
            }
            // Do not await after this final MainActor validation.
            accessState = state
            let revision = action.revision
            let publication = ContentPublication()
            contentPublication = publication
            let stillCurrent: @MainActor () -> Bool = { [weak self] in
                guard let self else { return false }
                return self.permitsContentPresentation && self.sceneIsActive
                    && self.presentationRevision === revision
                    && self.contentPublication === publication
                    && self.queuedLifecycleEvents.isEmpty
            }
            publishedBackupPreviewAccess = ContentAccess(token: backupToken, surface: .backupImport,
                                                         gate: session.gate, isCurrent: stillCurrent)
            let renderAccess = ContentAccess(token: token, surface: .render,
                                             gate: session.gate, isCurrent: stillCurrent)
            publishedRenderAccess = renderAccess
            if case .ready(let store, _, _) = startupRouter.route {
                publishedSceneNavigationAccess = SceneNavigationAccess(token: sceneToken,
                    isCurrent: stillCurrent, port: session.sceneNavigationStatePort(),
                    router: startupRouter, workspaceID: store.workspaceID, generationID: store.generationID)
                let myDayProvider = store.makeMyDaySourceProvider(accessGate: session.gate)
                publishedMyDayAccess = MyDayAccess(publicationAccess: renderAccess, provider: myDayProvider,
                    planning: store.makeMyDayPlanningCommitService(sourceProvider: myDayProvider))
            } else {
                publishedSceneNavigationAccess = nil
                publishedMyDayAccess = nil
            }
            permitsContentPresentation = true
        } catch {
            guard isCurrent(action) else { return }
            permitsContentPresentation = false
            publishedMyDayAccess = nil
            if action.resumesAfterInactive,
               (!sceneIsActive || action.revision !== presentationRevision
                    || !queuedLifecycleEvents.isEmpty) {
                retainPendingStartup(session, action: action)
                return
            }
            failure = .startup
        }
    }

    @discardableResult
    private func refreshState(
        _ session: ProductionAppAccessSessionV1,
        action: Action? = nil,
        expectedRevision: PresentationRevision? = nil
    ) async throws -> Bool {
        let setting = await session.setting.readAppLockSetting()
        let enabled: Bool?
        switch setting {
        case .absentDisabled:
            enabled = false
        case .value(let value):
            try value.validate()
            enabled = value.isEnabled
        case .corruptOrAmbiguous, .protectedDataUnavailable:
            enabled = nil
        }
        let state = await session.gate.currentState()
        if let action, !isCurrent(action) { return false }
        if let expectedRevision, expectedRevision !== presentationRevision { return false }
        settingIsEnabled = enabled
        accessState = state
        if !state.permitsContentAccess {
            permitsContentPresentation = false
            publishedMyDayAccess = nil
        }
        return true
    }

    private func beginLongAction(resumesAfterInactive: Bool) -> Action? {
        guard activeAction == nil else { return nil }
        let action = Action(hardEpoch: hardEpoch, revision: presentationRevision,
                            resumesAfterInactive: resumesAfterInactive)
        activeAction = action
        isBusy = true
        return action
    }

    private func finishLongAction(_ action: Action) {
        if activeAction === action {
            activeAction = nil
            isBusy = false
            schedulePendingStartupIfPossible()
        }
    }

    private func isCurrent(_ action: Action) -> Bool {
        activeAction === action && action.hardEpoch === hardEpoch
    }

    private func invalidateForHardRevocation() {
        hardEpoch = HardEpoch()
        activeAction = nil
        pendingAuthorizedStartup = nil
        isBusy = false
    }

    private func retainPendingStartup(_ session: ProductionAppAccessSessionV1, action: Action) {
        guard action.hardEpoch === hardEpoch else { return }
        pendingAuthorizedStartup = .init(session: session, hardEpoch: hardEpoch,
                                         resumesAfterInactive: action.resumesAfterInactive)
    }

    private func scheduleEligibleStartup(_ session: ProductionAppAccessSessionV1) {
        guard startupTask == nil, activeAction == nil, pendingErase == nil, queuedLifecycleEvents.isEmpty,
              sceneIsActive, failure == nil else { return }
        let epoch = hardEpoch
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.startupTask = nil
                self.schedulePendingStartupIfPossible()
            }
            guard epoch === self.hardEpoch, self.sceneIsActive,
                  self.queuedLifecycleEvents.isEmpty else { return }
            let state = await session.gate.currentState()
            guard epoch === self.hardEpoch, self.sceneIsActive,
                  self.queuedLifecycleEvents.isEmpty else { return }
            let pending = self.pendingAuthorizedStartup
            guard (pending?.hardEpoch === epoch && pending?.resumesAfterInactive == true)
                    || state == .disabled,
                  let action = self.beginLongAction(resumesAfterInactive: true) else {
                return
            }
            self.pendingAuthorizedStartup = nil
            await self.startAndPublish(session, action: action)
            self.finishLongAction(action)
        }
    }

    private func schedulePendingStartupIfPossible() {
        guard let pendingAuthorizedStartup, sceneIsActive,
              queuedLifecycleEvents.isEmpty, lifecycleDrainTask == nil else { return }
        scheduleEligibleStartup(pendingAuthorizedStartup.session)
    }
}

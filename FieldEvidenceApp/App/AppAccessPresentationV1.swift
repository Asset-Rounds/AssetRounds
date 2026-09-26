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
#if DEBUG
    /// Fixed recovery phase/type observations; no payloads or identifiers.
    var eraseRecoveryDiagnosticForTesting: (@MainActor (String) -> Void)?
#endif

    /// Captured by one presented Restore destination. A later foreground
    /// publication cannot authorize a callback retained by the older view.
    struct ContentAccess {
        private let token: AppAccessGateV1.ContentReadToken
        private let surface: AppAccessContentReadSurfaceV1
        private let gate: AppAccessGateV1
        private let isCurrent: @MainActor () -> Bool
        private let backupStore: StoreSessionCoordinator?

        fileprivate init(token: AppAccessGateV1.ContentReadToken,
                         surface: AppAccessContentReadSurfaceV1,
                         gate: AppAccessGateV1,
                         isCurrent: @escaping @MainActor () -> Bool,
                         backupStore: StoreSessionCoordinator? = nil) {
            self.token = token
            self.surface = surface
            self.gate = gate
            self.isCurrent = isCurrent
            self.backupStore = backupStore
        }

        @MainActor
        func isBound(to expectedGate: AppAccessGateV1) -> Bool { gate === expectedGate }

        @MainActor
        func withRead<T>(_ body: () throws -> T) throws -> T {
            try validateCurrentPublication()
            return try token.withContentRead(for: surface, body)
        }

        /// A nested synchronous validator already inside this token's read
        /// fence can check presentation retirement without locking it again.
        @MainActor
        fileprivate func validateCurrentPublication() throws {
            guard isCurrent() else { throw AppAccessContractFailureV1.accessDenied }
        }

        @MainActor
        fileprivate func reminderAuthorization() throws -> NotificationOperationAuthorizationV1 {
            guard surface == .render else { throw AppAccessContractFailureV1.accessDenied }
            try withRead {}
            return .init(gate: gate, proof: .content(token), operationID: UUID(), subject: nil)
        }

        /// Called only by the explicit backup action. The operation retains
        /// this publication, including its original revocation reference.
        @MainActor
        func beginBackupOperation(modelContext: ModelContext, generationRootURL: URL) throws -> BackupOperationAccess {
            try withRead {
                guard let backupStore, backupStore.modelContext === modelContext,
                      backupStore.generationRootURL == generationRootURL.standardizedFileURL else {
                    throw AppAccessContractFailureV1.accessDenied
                }
                return try BackupOperationAccess(content: self, store: backupStore, gate: gate)
            }
        }
    }
    typealias BackupPreviewAccess = ContentAccess

    struct ReminderSettingsSnapshot: Equatable, Sendable {
        let policy: DeviceLocalReminderPolicyV1
        let authorization: LocalReminderAuthorizationV1
        let appLockEnabled: Bool
    }

    /// Settings retains its original visible publication and concrete owners.
    /// A later foreground or completed Erase cannot refresh a held action.
    @MainActor
    final class ReminderSettingsAccess {
        let id = UUID()
        private let publication: ContentAccess
        private let owners: ProductionReminderSettingsOwnersV1
        private let currentOwners: @MainActor () -> ProductionReminderSettingsOwnersV1

        fileprivate init(publication: ContentAccess,
                         currentOwners: @escaping @MainActor () -> ProductionReminderSettingsOwnersV1) {
            self.publication = publication
            self.currentOwners = currentOwners
            owners = currentOwners()
        }

        private func validated<T>(_ body: () throws -> T) throws -> T {
            try Task.checkCancellation()
            return try publication.withRead {
                let current = currentOwners()
                guard current.preferences === owners.preferences,
                      current.notifications === owners.notifications else {
                    throw AppAccessContractFailureV1.accessDenied
                }
                return try body()
            }
        }

        func read() async throws -> ReminderSettingsSnapshot {
            let saved = try validated {
                (try owners.preferences.readReminderPolicy(), try owners.preferences.readAppLockSettingSnapshot())
            }
            let authorization = try publication.reminderAuthorization()
            let permission = try await owners.notifications.reminderAuthorization(authorization: authorization)
            try validated {
                guard try owners.preferences.readStoredReminderPolicy() == saved.0,
                      try owners.preferences.readAppLockSettingSnapshot() == saved.1 else {
                    throw SettingsContractFailureV1.staleRevision
                }
            }
            let appLockEnabled = try saved.1.setting?.isEnabled == true
            return .init(policy: saved.0, authorization: permission, appLockEnabled: appLockEnabled)
        }

        func update(expected: DeviceLocalReminderPolicyV1, isEnabled: Bool,
                    detail: ReminderNotificationDetailV1) async throws {
            try validated {
                guard try owners.preferences.readStoredReminderPolicy() == expected else {
                    throw SettingsContractFailureV1.staleRevision
                }
            }
            let authorization = try publication.reminderAuthorization()
            let request = ReminderPolicyEditRequestV1(expected: expected, isEnabled: isEnabled,
                detail: detail, operationID: UUID())
            let command = try await owners.preferences.authorizeReminderPolicyEdit(request)
            try validated {}
            if isEnabled && !expected.isEnabled {
                _ = try await owners.notifications.requestReminderAuthorization(authorization: authorization)
                try validated {}
            }
            // Do not nest the command's revocation lock under the render lock.
            // MainActor publication/owner checks cannot interleave here; the
            // sole Preferences leaf independently checks live edit authority.
            _ = try owners.preferences.updateReminderPolicy(command)
            try validated {}
            _ = try await owners.notifications.reconcileSavedReminderPolicy(authorization: authorization)
            try validated {}
        }

        func requestPermission() async throws {
            try validated {}
            let authorization = try publication.reminderAuthorization()
            _ = try await owners.notifications.requestReminderAuthorization(authorization: authorization)
            try validated {}
            _ = try await owners.notifications.reconcileSavedReminderPolicy(authorization: authorization)
            try validated {}
        }

        /// Explicit recovery of a saved choice. It never edits consent or
        /// prompts for permission, and retains this visible publication.
        func reconcileSavedPolicy() async throws {
            try validated {}
            let authorization = try publication.reminderAuthorization()
            _ = try await owners.notifications.reconcileSavedReminderPolicy(authorization: authorization)
            try validated {}
        }
    }

    /// A private-minted, nonportable action capability. It neither reacquires
    /// authentication nor adopts a replacement writer after an actor hop.
    @MainActor
    final class BackupOperationAccess {
        private let content: ContentAccess
        private let store: StoreSessionCoordinator
        private let writer: WorkspaceWriterV1
        private let generationID: UUID
        private let generationRootURL: URL
        private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
        private let gate: AppAccessGateV1
        private var holdingOriginalRead = false

        fileprivate init(content: ContentAccess, store: StoreSessionCoordinator, gate: AppAccessGateV1) throws {
            self.content = content; self.store = store; self.gate = gate
            writer = store.workspaceWriter; generationID = store.generationID
            generationRootURL = store.generationRootURL
            rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
            try validateStore()
        }

        private func validateStore() throws {
            try Task.checkCancellation()
            guard store.workspaceWriter === writer, store.generationID == generationID,
                  store.generationRootURL == generationRootURL, !store.modelContext.hasChanges,
                  try writer.currentRevision().generationID == generationID,
                  try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL) == rootIdentity else {
                throw BackupExportServiceError.generationLeaseLost
            }
        }

        func validate(for expectedStore: StoreSessionCoordinator) throws {
            guard expectedStore === store else { throw AppAccessContractFailureV1.accessDenied }
            // Publication validators run inside the same synchronous access ->
            // generation -> path locks. Never recursively acquire the NSLock.
            if holdingOriginalRead { try validateStore() }
            else { try content.withRead { try validateStore() } }
        }

        func withAuthorization<T>(_ body: (StoreSessionCoordinator) throws -> T) throws -> T {
            guard !holdingOriginalRead else { throw AppAccessContractFailureV1.accessDenied }
            return try content.withRead {
                holdingOriginalRead = true
                defer { holdingOriginalRead = false }
                try validateStore()
                return try body(store)
            }
        }

        func makePhotoService(parentCheckpoint: FieldDraftCheckpointV1,
                              staging: DraftAttachmentStagingAdapterV1) throws -> ProductionCheckRunnerItemDraftServiceV1 {
            try withAuthorization { store in
                try store.makePhotoBackupService(parentCheckpoint: parentCheckpoint, accessGate: gate, staging: staging)
            }
        }
    }

    /// One synchronous item effect remains inside the original publication's
    /// read fence. The next asynchronous step must enter this scope again.
    @MainActor
    final class CheckRunnerItemOperationAccess: CheckRunnerItemOperationScopeV1 {
        private let content: ContentAccess
        private let store: StoreSessionCoordinator
        private let writer: WorkspaceWriterV1
        private let service: ProductionCheckRunnerItemDraftServiceV1
        private let progress: ProductionRepetitiveCaptureProgressServiceV2
        private let scene: AppShellSceneStateV1
        private let target: NavigationTargetV1
        private let snapshot: SceneNavigationSnapshotV1
        private var holdingOriginalRead = false
#if DEBUG
        /// Runs after real off-main preparation, before any live file effect.
        var beforeFinalizationPreparationPublicationForTesting: (() throws -> Void)?
#endif

        /// The finalizer must publish into the original store's generation,
        /// under the same content -> generation order as live photo effects.
        func withFinalizationAuthorization<T>(generationID: UUID, generationRootURL: URL,
                                              _ body: () throws -> T) throws -> T {
            try withFinalizationWriterAuthorization(writer, generationID: generationID,
                generationRootURL: generationRootURL) {
                try store.withCheckRunnerPhotoPublication(expectedWriter: writer,
                    applicationSupportURL: store.checkRunnerPhotoApplicationSupportURL, body)
            }
        }

        /// The writer acquires its own generation fence for database commits.
        /// Keep its entire synchronous call inside the original content scope,
        /// without adding a redundant outer generation fence.
        func withFinalizationWriterAuthorization<T>(_ expectedWriter: WorkspaceWriterV1,
            generationID: UUID, generationRootURL: URL, _ body: () throws -> T) throws -> T {
            try withAuthorization {
                guard writer === expectedWriter, store.generationID == generationID,
                      store.generationRootURL.standardizedFileURL == generationRootURL.standardizedFileURL else {
                    throw AppAccessContractFailureV1.accessDenied
                }
                return try body()
            }
        }

        /// Called inside the finalizer's generation fence immediately before
        /// rollback effects. A durable save always wins over a lost response.
        func requireUncommittedFinalization(mutationID: UUID) throws {
            try withAuthorization {
                guard try writer.durableReceipt(mutationID: .init(rawValue: mutationID)) == nil else {
                    throw AppAccessContractFailureV1.accessDenied
                }
            }
        }

        func requireCommittedFinalization(binding: FinalizationWriterCommitBindingV1) throws {
            try withAuthorization {
                guard try writer.finalizationCommitReceipt(binding) != nil else {
                    throw AppAccessContractFailureV1.accessDenied
                }
            }
        }

        fileprivate init(content: ContentAccess, store: StoreSessionCoordinator,
            service: ProductionCheckRunnerItemDraftServiceV1,
            progress: ProductionRepetitiveCaptureProgressServiceV2,
            scene: AppShellSceneStateV1, target: NavigationTargetV1,
            snapshot: SceneNavigationSnapshotV1) {
            self.content = content; self.store = store; self.writer = store.workspaceWriter
            self.service = service; self.progress = progress
            self.scene = scene; self.target = target; self.snapshot = snapshot
        }

        private func validateInsidePublication() throws {
            try Task.checkCancellation()
            try content.validateCurrentPublication()
            guard scene.snapshot == snapshot, store.workspaceWriter === writer else {
                throw AppAccessContractFailureV1.accessDenied
            }
            try progress.validateCheckRunnerOwner(writer: writer, modelContext: store.modelContext)
            try service.validateFinalizationOwner(progress)
            try service.validateLiveTarget(target)
        }

        func withAuthorization<T>(_ body: () throws -> T) throws -> T {
            if holdingOriginalRead {
                // Editor/service validators may re-enter during this same
                // synchronous effect. Do not recursively lock the gate or
                // persisted scene port; still reject an in-memory scene change.
                try validateInsidePublication()
                return try body()
            }
            try Task.checkCancellation()
            try scene.validatePersistedIntent(target, expectedSnapshot: snapshot)
            return try content.withRead {
                holdingOriginalRead = true
                defer { holdingOriginalRead = false }
                try validateInsidePublication()
                return try body()
            }
        }

        func withAuthorization<T>(for expectedService: ProductionCheckRunnerItemDraftServiceV1,
            _ body: () throws -> T) throws -> T {
            guard expectedService === service else { throw AppAccessContractFailureV1.accessDenied }
            return try withAuthorization(body)
        }
    }

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

    /// Round reads retain the visible render publication while the underlying
    /// authority performs its own operation-scoped source validation.
    @MainActor
    struct RoundAccess {
        /// A single derived readiness result and its non-forgeable, per-read
        /// publication evidence. Consumers expose only `manifest` and must
        /// validate the value synchronously before visible assignment.
        struct RoundReadinessReadV1 {
            let manifest: OfflineReadinessManifestV1
            fileprivate let publicationEvidence: ProductionOfflineReadinessPublicationEvidenceV1
        }

        @MainActor
        struct RepetitiveCaptureLaunchV2 {
            fileprivate let write: PreparedRepetitiveCaptureSourceV2
            fileprivate let readiness: RoundReadinessReadV1
            var checkpoint: FieldDraftCheckpointV1 { write.checkpoint }
            var attemptState: RepetitiveCaptureCheckpointAttemptStateV2 { write.attemptState }
        }

        @MainActor
        struct RepetitiveCaptureStepV2 {
            fileprivate let write: PreparedRepetitiveCaptureStepV2
            fileprivate let readiness: RoundReadinessReadV1
            var checkpoint: FieldDraftCheckpointV1 { write.checkpoint }
            var step: RepetitiveCaptureProgressStepV2 { write.step }
            var attemptState: RepetitiveCaptureCheckpointAttemptStateV2 { write.attemptState }
        }

        @MainActor
        struct RepetitiveCaptureContinuationLaunchV1 {
            fileprivate let write: PreparedRepetitiveCaptureDestinationContinuationV1
            fileprivate let readiness: RoundReadinessReadV1
            var checkpoint: FieldDraftCheckpointV1 { write.proposal.checkpoint }
            var attemptState: RepetitiveCaptureCheckpointAttemptStateV2 { write.attemptState }
        }

        struct RepetitiveCaptureProgressResultV2 {
            let progress: ProductionRepetitiveCaptureReadV2
            fileprivate let readiness: RoundReadinessReadV1
        }

        private let publicationAccess: ContentAccess
        private let readinessAuthority: ProductionOfflineReadinessAuthorityV1
        private let draftOrdering: ProductionRoundDraftOrderingServiceV1?
        private let sessionTransitions: ProductionRoundSessionTransitionServiceV1?
        private let repetitiveCapture: ProductionRepetitiveCaptureProgressServiceV2?
        private let itemStore: StoreSessionCoordinator

        #if DEBUG
        func repetitiveCaptureOwnerForTesting() throws -> ProductionRepetitiveCaptureProgressServiceV2 {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return repetitiveCapture
            }
        }
        private final class DraftOrderingDebugHooks {
            var afterReceipt: (@MainActor () throws -> Void)?
        }
        private let draftOrderingDebugHooks = DraftOrderingDebugHooks()
        private final class SessionTransitionDebugHooks {
            var afterReceipt: (@MainActor () throws -> Void)?
        }
        private let sessionTransitionDebugHooks = SessionTransitionDebugHooks()
        private final class RepetitiveCaptureDebugHooks {
            var afterSourceReceipt: (@MainActor () throws -> Void)?
            var afterStepReceipt: (@MainActor () throws -> Void)?
        }
        private let repetitiveCaptureDebugHooks = RepetitiveCaptureDebugHooks()
        #endif

        fileprivate init(
            publicationAccess: ContentAccess,
            readinessAuthority: ProductionOfflineReadinessAuthorityV1,
            draftOrdering: ProductionRoundDraftOrderingServiceV1?,
            sessionTransitions: ProductionRoundSessionTransitionServiceV1?,
            repetitiveCapture: ProductionRepetitiveCaptureProgressServiceV2?,
            itemStore: StoreSessionCoordinator
        ) {
            self.publicationAccess = publicationAccess
            self.readinessAuthority = readinessAuthority
            self.draftOrdering = draftOrdering
            self.sessionTransitions = sessionTransitions
            self.repetitiveCapture = repetitiveCapture
            self.itemStore = itemStore
        }

        /// Presentation availability only. Every command remains fenced by
        /// the original publication at invocation time.
        var supportsDraftOrdering: Bool { draftOrdering != nil }
        var supportsSessionTransitions: Bool { sessionTransitions != nil }
        var supportsRepetitiveCaptureProgress: Bool { repetitiveCapture != nil }

        func makeCheckRunnerItemService(source: CheckRunnerRoundItemSourceV1) throws
            -> ProductionCheckRunnerItemDraftServiceV1 {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try itemStore.makeLiveCheckRunnerItemService(source: source, progress: repetitiveCapture)
            }
        }

        /// Read only: authenticated capture sources already launched for this Round.
        func readRepetitiveCaptureSources(round: RoundSessionV1) throws -> [ProductionRepetitiveCaptureReadV2] {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try repetitiveCapture.sources(roundSessionID: round.sessionID)
            }
        }

        /// Read only, before any launch or ENTRY write for this item.
        func validateCheckRunnerItemEntry(round: RoundSessionV1, itemID: UUID) throws {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                try itemStore.validateLiveCheckRunnerItemEntry(round: round, itemID: itemID,
                    progress: repetitiveCapture)
            }
        }

        /// Read only: the frozen check/recheck source for the chain's current ENTRY item.
        func captureCheckRunnerItemSource(read: ProductionRepetitiveCaptureReadV2, itemID: UUID) throws
            -> CheckRunnerRoundItemSourceV1 {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                try repetitiveCapture.validateForPublication(read)
                return try itemStore.captureLiveCheckRunnerItemSource(read: read, itemID: itemID,
                    progress: repetitiveCapture)
            }
        }

        func captureCheckRunnerItemOperation(service: ProductionCheckRunnerItemDraftServiceV1,
            scene: AppShellSceneStateV1, target: NavigationTargetV1) throws -> CheckRunnerItemOperationAccess {
            guard let repetitiveCapture, let snapshot = scene.snapshot else {
                throw AppAccessContractFailureV1.accessDenied
            }
            let operation = CheckRunnerItemOperationAccess(content: publicationAccess, store: itemStore,
                service: service, progress: repetitiveCapture, scene: scene, target: target, snapshot: snapshot)
            try operation.withAuthorization {}
            return operation
        }

        func readRepetitiveCaptureDestinationReview(reference: MyDayEligibleReferenceV1) throws
            -> RepetitiveCaptureReviewLineageV1? {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try repetitiveCapture.destinationReview(reference: reference)
            }
        }

        func readRepetitiveCaptureDestinationReview(reviewDraftID: UUID) throws -> RepetitiveCaptureReviewLineageV1 {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try repetitiveCapture.destinationReview(reviewDraftID: reviewDraftID)
            }
        }

        func prepareRepetitiveCaptureDestinationResolution(reviewDraftID: UUID,
            plan: DraftConflictResolutionPlanV1, round: RoundSessionV1?) throws
            -> PreparedRepetitiveCaptureDestinationResolutionV1 {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try repetitiveCapture.prepareDestinationResolution(
                    reviewDraftID: reviewDraftID, plan: plan, round: round)
            }
        }

        func persistRepetitiveCaptureDestinationResolution(_ prepared: PreparedRepetitiveCaptureDestinationResolutionV1,
            validateIntent: @MainActor () throws -> Void) throws -> ProductionRepetitiveCaptureResolutionReadV1 {
            guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
            try Task.checkCancellation(); try validateIntent()
            if let original = try publicationAccess.withRead({
                try repetitiveCapture.committedDestinationResolution(prepared)
            }) { return original }
            let result = try publicationAccess.withRead { try repetitiveCapture.persistDestinationResolution(prepared) }
            try validateIntent()
            try publicationAccess.withRead { try repetitiveCapture.validateForPublication(result) }
            return result
        }

        func readRepetitiveCaptureDestinationDiscard(reviewDraftID: UUID) throws
            -> ProductionRepetitiveCaptureDiscardReadV1? {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try repetitiveCapture.destinationDiscard(reviewDraftID: reviewDraftID)
            }
        }

        func prepareRepetitiveCaptureDestinationDiscard(reviewDraftID: UUID) throws
            -> PreparedRepetitiveCaptureDestinationDiscardV1 {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try repetitiveCapture.prepareDestinationDiscard(reviewDraftID: reviewDraftID)
            }
        }

        func persistRepetitiveCaptureDestinationDiscard(_ prepared: PreparedRepetitiveCaptureDestinationDiscardV1,
            confirmed: Bool, validateIntent: @MainActor () throws -> Void) throws -> ProductionRepetitiveCaptureDiscardReadV1 {
            guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
            try Task.checkCancellation(); try validateIntent()
            if let original = try publicationAccess.withRead({
                try repetitiveCapture.committedDestinationDiscard(prepared)
            }) { return original }
            let result = try publicationAccess.withRead {
                try repetitiveCapture.persistDestinationDiscard(prepared, confirmed: confirmed)
            }
            try validateIntent()
            try publicationAccess.withRead { try repetitiveCapture.validateForPublication(result) }
            return result
        }

        func readRepetitiveCaptureDestinationContinuation(reviewDraftID: UUID) throws
            -> ProductionRepetitiveCaptureContinuationReadV1? {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try repetitiveCapture.destinationContinuation(reviewDraftID: reviewDraftID)
            }
        }

        func prepareRepetitiveCaptureDestinationContinuation(reviewDraftID: UUID, round: RoundSessionV1,
                                                              readiness: RoundReadinessReadV1) throws
            -> RepetitiveCaptureContinuationLaunchV1 {
            try validateReadinessForPublication(readiness)
            return try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                try readinessAuthority.validateSessionForPublication(round)
                return .init(write: try repetitiveCapture.prepareDestinationContinuation(
                    reviewDraftID: reviewDraftID, round: round, manifest: readiness.manifest), readiness: readiness)
            }
        }

        func persistRepetitiveCaptureDestinationContinuation(_ launch: RepetitiveCaptureContinuationLaunchV1,
                                                              validateIntent: @MainActor () throws -> Void) throws
            -> ProductionRepetitiveCaptureContinuationReadV1 {
            guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
            try Task.checkCancellation(); try validateIntent()
            if let committed = try publicationAccess.withRead({
                try repetitiveCapture.committedDestinationContinuation(launch.write)
            }) { return committed }
            try validateReadinessForPublication(launch.readiness)
            let result = try publicationAccess.withRead { try repetitiveCapture.persistDestinationContinuation(launch.write) }
            #if DEBUG
            try repetitiveCaptureDebugHooks.afterSourceReceipt?()
            #endif
            try validateIntent()
            try publicationAccess.withRead { try repetitiveCapture.validateForPublication(result) }
            return result
        }

        func prepareRepetitiveCaptureLaunch(round: RoundSessionV1, readiness: RoundReadinessReadV1) throws
            -> RepetitiveCaptureLaunchV2 {
            try validateReadinessForPublication(readiness)
            return try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                try readinessAuthority.validateSessionForPublication(round)
                return .init(write: try repetitiveCapture.prepareSource(round: round, manifest: readiness.manifest),
                             readiness: readiness)
            }
        }

        /// Exact receipt replay acknowledges a source checkpoint; it does not
        /// re-grant entry using the now-stale pre-checkpoint readiness evidence.
        func persistRepetitiveCaptureLaunch(_ launch: RepetitiveCaptureLaunchV2,
                                            validateIntent: @MainActor () throws -> Void) throws
            -> ProductionRepetitiveCaptureReadV2 {
            guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
            try Task.checkCancellation(); try validateIntent()
            if let committed = try publicationAccess.withRead({ try repetitiveCapture.committedSource(launch.write) }) {
                return committed
            }
            try validateReadinessForPublication(launch.readiness)
            let result = try publicationAccess.withRead { try repetitiveCapture.persistSource(launch.write) }
            #if DEBUG
            try repetitiveCaptureDebugHooks.afterSourceReceipt?()
            #endif
            try validateIntent()
            try publicationAccess.withRead { try repetitiveCapture.validateForPublication(result) }
            return result
        }

        func readRepetitiveCaptureProgress(sourceDraftID: UUID) throws -> ProductionRepetitiveCaptureReadV2 {
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return try repetitiveCapture.read(sourceDraftID: sourceDraftID)
            }
        }

        func prepareCheckRunnerFinalization(service: ProductionCheckRunnerItemDraftServiceV1,
            draftID: UUID, expectedCheckpointSHA256: String, sourceApp: SourceAppSnapshotV1,
            authorizing liveOperation: CheckRunnerItemOperationAccess? = nil,
            validateIntent: @MainActor () throws -> Void) async throws -> FieldDraftCheckpointV1 {
            guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
            func validate() throws {
                try Task.checkCancellation(); try validateIntent()
                if let liveOperation {
                    try liveOperation.withAuthorization(for: service) {
                        try service.validateFinalizationOwner(repetitiveCapture)
                    }
                } else {
                    try publicationAccess.withRead { try service.validateFinalizationOwner(repetitiveCapture) }
                }
            }
            try validate()
            let result = try await service.prepareFinalization(draftID: draftID,
                expectedCheckpointSHA256: expectedCheckpointSHA256, sourceApp: sourceApp,
                authorizing: liveOperation, validateIntent: validate)
            try validate()
            return result
        }

        /// The original publication owns both effects. Uncertain progress is
        /// retried from its original COMPLETE checkpoint without refinalizing.
        func resumeCheckRunnerFinalization(service: ProductionCheckRunnerItemDraftServiceV1,
            draftID: UUID, focus: RepetitiveCaptureRequirementFocusV1, recordedByName: String,
            authorizing liveOperation: CheckRunnerItemOperationAccess? = nil,
            validateIntent: @escaping @MainActor () throws -> Void) async throws -> RepetitiveCaptureProgressResultV2 {
            guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
            func withItemRead<T>(_ body: () throws -> T) throws -> T {
                if let liveOperation { return try liveOperation.withAuthorization(for: service, body) }
                return try publicationAccess.withRead(body)
            }
            let validate: @MainActor () throws -> Void = {
                try Task.checkCancellation(); try validateIntent()
                if let liveOperation {
                    try liveOperation.withAuthorization(for: service) {
                        try service.validateFinalizationOwner(repetitiveCapture)
                    }
                } else {
                    try self.publicationAccess.withRead { try service.validateFinalizationOwner(repetitiveCapture) }
                }
            }
            try validate()
            _ = try await service.resumeFinalization(draftID: draftID,
                authorizing: liveOperation, validateIntent: validate)
            try validate()
            let terminal = try withItemRead {
                try service.terminalFinalizationSource(draftID: draftID, progress: repetitiveCapture,
                    authorizing: liveOperation)
            }
            let read = try readRepetitiveCaptureProgress(sourceDraftID: terminal.source.sourceCheckpoint.draftID)
            if let checkpoint = try withItemRead({
                try repetitiveCapture.checkRunnerCompletion(read: read, source: terminal.source, recordID: terminal.recordID)
            }) {
                return try await resumeRepetitiveCaptureProgress(sourceDraftID: terminal.source.sourceCheckpoint.draftID,
                    stepDraftID: checkpoint.draftID, validateIntent: validate)
            }
            let readiness = try await rebuildReadiness(for: read.chain.currentRound, previous: nil)
            try validate()
            try withItemRead {
                let refreshed = try service.terminalFinalizationSource(draftID: draftID, progress: repetitiveCapture,
                    authorizing: liveOperation)
                guard refreshed.source == terminal.source, refreshed.recordID == terminal.recordID else {
                    throw ScanToWorkFailureV1.stale
                }
                try repetitiveCapture.validateForPublication(read)
            }
            let step = try prepareRepetitiveCaptureStep(read: read, readiness: readiness, action: .complete,
                focus: focus, completionRecordID: terminal.recordID, recordedByName: recordedByName)
            return try await executeRepetitiveCaptureStep(step, validateIntent: validate)
        }

        func prepareRepetitiveCaptureStep(read: ProductionRepetitiveCaptureReadV2,
            readiness: RoundReadinessReadV1, action: RepetitiveCaptureProgressActionV2,
            focus: RepetitiveCaptureRequirementFocusV1, completionRecordID: UUID? = nil,
            recordedByName: String) throws -> RepetitiveCaptureStepV2 {
            try requireRepetitiveCaptureReadiness(readiness, round: read.chain.currentRound)
            return try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                return .init(write: try repetitiveCapture.prepareStep(read: read, action: action, focus: focus,
                    completionRecordID: completionRecordID, recordedByName: recordedByName), readiness: readiness)
            }
        }

        func executeRepetitiveCaptureStep(_ prepared: RepetitiveCaptureStepV2,
                                         validateIntent: @MainActor () throws -> Void) async throws
            -> RepetitiveCaptureProgressResultV2 {
            guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
            try Task.checkCancellation(); try validateIntent()
            let committed = try publicationAccess.withRead { try repetitiveCapture.committedStep(prepared.write) }
            if committed == nil {
                try requireRepetitiveCaptureReadiness(prepared.readiness, round: prepared.step.expectedRound)
                _ = try publicationAccess.withRead { try repetitiveCapture.persistStep(prepared.write) }
                #if DEBUG
                try repetitiveCaptureDebugHooks.afterStepReceipt?()
                #endif
            }
            return try await resumeRepetitiveCaptureProgress(sourceDraftID: prepared.step.source.draftID,
                stepDraftID: prepared.checkpoint.draftID, validateIntent: validateIntent)
        }

        /// An explicit action. Merely reading a cold chain never calls this.
        func resumeRepetitiveCaptureProgress(sourceDraftID: UUID, stepDraftID: UUID,
                                             validateIntent: @MainActor () throws -> Void) async throws
            -> RepetitiveCaptureProgressResultV2 {
            guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
            try Task.checkCancellation(); try validateIntent()
            let initial = try readRepetitiveCaptureProgress(sourceDraftID: sourceDraftID)
            guard let tip = initial.chain.nodes.last, tip.checkpoint.draftID == stepDraftID else {
                throw ScanToWorkFailureV1.stale
            }
            let beforeReadiness = try await rebuildReadiness(for: initial.chain.currentRound, previous: nil)
            try requireRepetitiveCaptureReadiness(beforeReadiness, round: initial.chain.currentRound)
            try publicationAccess.withRead { try repetitiveCapture.validateForPublication(initial) }
            try Task.checkCancellation(); try validateIntent()
            if tip.isPendingRoundEffect {
                let transition = try publicationAccess.withRead {
                    try repetitiveCapture.pendingTransition(sourceDraftID: sourceDraftID, stepDraftID: stepDraftID)
                }
                let receipt = try await executeSessionTransition(transition) {
                    try requireRepetitiveCaptureReadiness(beforeReadiness, round: initial.chain.currentRound)
                    try publicationAccess.withRead { try repetitiveCapture.validateForPublication(initial) }
                    try validateIntent()
                }
                let after = try readRepetitiveCaptureProgress(sourceDraftID: sourceDraftID)
                guard after.chain.nodes.last?.checkpoint.draftID == stepDraftID,
                      after.chain.nodes.last?.roundReceipt == receipt else { throw ScanToWorkFailureV1.authorityMismatch }
                let afterReadiness = try await rebuildReadiness(for: after.chain.currentRound, previous: nil)
                let result = RepetitiveCaptureProgressResultV2(progress: after, readiness: afterReadiness)
                try Task.checkCancellation(); try validateIntent()
                try validateRepetitiveCaptureProgressForPublication(result)
                return result
            }
            let result = RepetitiveCaptureProgressResultV2(progress: initial, readiness: beforeReadiness)
            try Task.checkCancellation(); try validateIntent()
            try validateRepetitiveCaptureProgressForPublication(result)
            return result
        }

        func validateRepetitiveCaptureProgressForPublication(_ result: RepetitiveCaptureProgressResultV2) throws {
            try requireRepetitiveCaptureReadiness(result.readiness, round: result.progress.chain.currentRound)
            try publicationAccess.withRead {
                guard let repetitiveCapture else { throw AppAccessContractFailureV1.accessDenied }
                try repetitiveCapture.validateForPublication(result.progress)
            }
        }

        private func requireRepetitiveCaptureReadiness(_ read: RoundReadinessReadV1, round: RoundSessionV1) throws {
            try validateReadinessForPublication(read)
            guard read.manifest.session == (try round.reference) else { throw ScanToWorkFailureV1.stale }
            for item in round.items { _ = try read.manifest.scanToWorkProof(assetID: item.selection.assetID) }
        }

        func prepareSessionTransition(expected: RoundSessionV1, transition: RoundSessionTransitionV1,
                                      recordedByName: String) throws -> PreparedRoundSessionTransitionV1 {
            try publicationAccess.withRead {
                guard let sessionTransitions else { throw AppAccessContractFailureV1.accessDenied }
                return try sessionTransitions.prepare(expected: expected, transition: transition,
                                                      recordedByName: recordedByName)
            }
        }

        func prepareItemTransition(expected: RoundSessionV1, itemID: UUID,
                                   transition: RoundSessionTransitionV1, reason: RoundItemReasonV1? = nil,
                                   completion: RoundItemCompletionReferenceV1? = nil,
                                   recordedByName: String) throws -> PreparedRoundSessionTransitionV1 {
            try publicationAccess.withRead {
                guard let sessionTransitions else { throw AppAccessContractFailureV1.accessDenied }
                return try sessionTransitions.prepareItem(expected: expected, itemID: itemID,
                    transition: transition, reason: reason, completion: completion,
                    recordedByName: recordedByName)
            }
        }

        func executeSessionTransition(_ write: PreparedRoundSessionTransitionV1,
                                      validateIntent: @MainActor () throws -> Void) async throws -> RoundSessionMutationReceiptV1 {
            guard let sessionTransitions else { throw AppAccessContractFailureV1.accessDenied }
            let result = try await sessionTransitions.execute(write, authorizing: publicationAccess,
                                                              validateIntent: validateIntent)
            #if DEBUG
            try sessionTransitionDebugHooks.afterReceipt?()
            #endif
            try sessionTransitions.validateForPublication(result, authorizing: publicationAccess)
            return result.receipt
        }

        func prepareDraftReorder(expected: RoundSessionV1, itemID: UUID, delta: Int,
                                 recordedByName: String) throws -> PreparedRoundDraftReorderV1 {
            try publicationAccess.withRead {
                guard let draftOrdering else { throw AppAccessContractFailureV1.accessDenied }
                return try draftOrdering.prepare(expected: expected, itemID: itemID, delta: delta,
                                          recordedByName: recordedByName)
            }
        }

        func executeDraftReorder(_ write: PreparedRoundDraftReorderV1,
                                 validateIntent: @MainActor () throws -> Void) async throws -> RoundSessionMutationReceiptV1 {
            guard let draftOrdering else { throw AppAccessContractFailureV1.accessDenied }
            let result = try await draftOrdering.execute(write, authorizing: publicationAccess,
                                                         validateIntent: validateIntent)
            #if DEBUG
            try draftOrderingDebugHooks.afterReceipt?()
            #endif
            try draftOrdering.validateForPublication(result, authorizing: publicationAccess)
            return result.receipt
        }

        func readSession(
            sessionID: UUID,
            expectedRevision: UInt64?
        ) async throws -> RoundSessionV1 {
            try publicationAccess.withRead {}
            let session = try await readinessAuthority.readSession(
                sessionID: sessionID,
                expectedRevision: expectedRevision
            )
            try publicationAccess.withRead {}
            return session
        }

        func rebuildReadiness(
            for session: RoundSessionV1,
            previous: OfflineReadinessManifestV1?
        ) async throws -> RoundReadinessReadV1 {
            try publicationAccess.withRead {}
            let result = try await readinessAuthority.rebuildReadiness(
                for: session,
                previous: previous
            )
            try publicationAccess.withRead {}
            return .init(
                manifest: result.manifest,
                publicationEvidence: result.publicationEvidence
            )
        }

        /// Final synchronous frontier fence for a caller that is about to
        /// assign a read session or its derived readiness to visible state.
        /// This retains the original publication access while the authority
        /// proves the complete canonical session reference is still current.
        func validateSessionForPublication(_ expected: RoundSessionV1) throws {
            try publicationAccess.withRead {
                try readinessAuthority.validateSessionForPublication(expected)
            }
        }

        #if DEBUG
        /// Runs after the real writer receipt returns and outside the store
        /// content hold, so a test can model lost acknowledgement without
        /// reentering an original token.
        func setAfterDraftReorderReceiptForTesting(_ hook: (@MainActor () throws -> Void)?) {
            draftOrderingDebugHooks.afterReceipt = hook
        }

        func setAfterDraftReorderContentResolutionForTesting(
            _ hook: (@MainActor () async throws -> Void)?
        ) { draftOrdering?.afterContentResolutionForTesting = hook }

        func setAfterDraftReorderContentMaterializationForTesting(
            _ hook: (@MainActor () async throws -> Void)?
        ) { draftOrdering?.afterContentMaterializationForTesting = hook }

        func setAfterSessionTransitionReceiptForTesting(_ hook: (@MainActor () throws -> Void)?) {
            sessionTransitionDebugHooks.afterReceipt = hook
        }
        func setAfterRepetitiveCaptureSourceReceiptForTesting(_ hook: (@MainActor () throws -> Void)?) {
            repetitiveCaptureDebugHooks.afterSourceReceipt = hook
        }
        func setAfterRepetitiveCaptureStepReceiptForTesting(_ hook: (@MainActor () throws -> Void)?) {
            repetitiveCaptureDebugHooks.afterStepReceipt = hook
        }
        func setAfterSessionTransitionContentResolutionForTesting(
            _ hook: (@MainActor () async throws -> Void)?
        ) { sessionTransitions?.afterContentResolutionForTesting = hook }
        func setAfterSessionTransitionContentMaterializationForTesting(
            _ hook: (@MainActor () async throws -> Void)?
        ) { sessionTransitions?.afterContentMaterializationForTesting = hook }
        #endif

        /// Final synchronous derived-read fence immediately before assigning
        /// this readiness result to visible state.
        func validateReadinessForPublication(_ read: RoundReadinessReadV1) throws {
            // Validate the original operation token before acquiring the
            // distinct visible-publication hold. These scopes must remain
            // sequential: neither holds the other's nonrecursive reference.
            try read.publicationEvidence.operationToken.withContentRead(for: .render) {}
            try publicationAccess.withRead {
                try readinessAuthority.validateReadinessForPublication(
                    read.publicationEvidence,
                    manifest: read.manifest
                )
            }
        }

        #if DEBUG
        /// Test-only suspension at the real source/read fence; it cannot
        /// supply source values or bypass the authority's final validation.
        func setAfterRoundSessionSourceObservationForTesting(
            _ hook: (@MainActor () async throws -> Void)?
        ) {
            readinessAuthority.afterRoundSessionSourceObservationForTesting = hook
        }

        /// Test-only suspension after materialization and before the original
        /// read token is revalidated for publication.
        func setAfterRoundReadinessMaterializationForTesting(
            _ hook: (@MainActor () async throws -> Void)?
        ) {
            readinessAuthority.afterRoundReadinessMaterializationForTesting = hook
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
    private var publishedRoundAccess: RoundAccess?
    private var publishedReminderSettingsAccess: ReminderSettingsAccess?
    /// Created once only after a store has reached an authorized render
    /// publication. A failed attempt remains unavailable for that publication
    /// and may be retried by a later eligible publication.
    private var roundReadinessLedger: OwnedStorageLedgerV1?
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
    var roundAccess: RoundAccess? {
        permitsContentPresentation ? publishedRoundAccess : nil
    }
    var reminderSettingsAccess: ReminderSettingsAccess? {
        permitsContentPresentation ? publishedReminderSettingsAccess : nil
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
        var cleanupActivationRefreshed = false
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
#if DEBUG
    private var terminatedForTesting = false
    private var startupActionForTesting: Action?

    /// Test teardown must join this owner's tasks, not infer drain from a
    /// covered/checking route. Hard revocation remains the real authority.
    func terminateAndDrainForTesting() async -> Bool {
        // These handles do not own callers executing restore/unlock/erase.
        // Capture that limitation before termination clears activeAction.
        let hasUnjoinedAction = pendingErase != nil
            || (activeAction != nil && activeAction !== startupActionForTesting)
        terminatedForTesting = true
        receive(.termination)
        let bootstrap = bootstrapTask
        let startup = startupTask
        bootstrap?.cancel()
        lifecycleDrainTask?.cancel()
        startup?.cancel()
        await bootstrap?.value
        // Bootstrap can schedule the lifecycle drain before its task exits.
        let lifecycle = lifecycleDrainTask
        lifecycle?.cancel()
        await lifecycle?.value
        await startup?.value
        let trailingLifecycle = lifecycleDrainTask
        trailingLifecycle?.cancel()
        await trailingLifecycle?.value
        // Retry only the router's existing exact-owner cleanup after all task
        // frames have returned; callers never release an arbitrary writer.
        startupRouter.pauseForAppAccess(discardPrepared: true)
        return !hasUnjoinedAction && pendingErase == nil && startupActionForTesting == nil
            && bootstrapTask == nil && lifecycleDrainTask == nil && startupTask == nil
            && !startupRouter.hasPendingWriterCleanup && !permitsContentPresentation
    }
#endif
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

    /// `authenticationClient` is nil in production, which composes the system
    /// Local Authentication client. Only the DEBUG UI-test launch hook in
    /// `FieldEvidenceAppApp` supplies one; the composition path is unchanged.
    init(
        startupRouter: StartupRouter,
        applicationSupportURL: URL,
        defaults: UserDefaults = .standard,
        authenticationClient: (any LocalAuthenticationClient)? = nil
    ) {
        self.startupRouter = startupRouter
        roundReadinessLedger = nil
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
                defaults: defaults,
                authenticationClient: authenticationClient
            )
        }
    }

    init(startupRouter: StartupRouter, eraseServiceFactory: EraseServiceFactory? = nil,
         restoreServiceFactory: @escaping RestoreServiceFactory = { try BackupRestoreService(applicationSupportURL: $0) },
         sessionFactory: @escaping SessionFactory) {
        self.startupRouter = startupRouter
        roundReadinessLedger = nil
        self.eraseServiceFactory = eraseServiceFactory
        self.restoreServiceFactory = restoreServiceFactory
        self.sessionFactory = sessionFactory
    }

    func bootstrapIfNeeded() async {
#if DEBUG
        guard !terminatedForTesting else { return }
#endif
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
        publishedRoundAccess = nil
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
                publishedRoundAccess = nil
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
                publishedRoundAccess = nil
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
            publishedRoundAccess = nil
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
        publishedRoundAccess = nil
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
                prepareCleanup: { [weak self, weak pending] in
                    guard let self, let pending, self.pendingErase === pending else {
                        throw AppAccessContractFailureV1.staleAttempt
                    }
                    try self.startupRouter.prepareErasedSessionCleanup(pending.ticket)
                },
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
            publishedRoundAccess = nil
            if let receipt = pending.abortedAdmission {
                do {
                    try await session.lifecycle.abandonEraseAdmission(receipt)
                    try startupRouter.cancelAbortedErase(pending.ticket, receipt: receipt)
                    if pendingErase === pending { pendingErase = nil }
                } catch { /* An unaccepted abort proof remains owned for retry. */ }
            } else if pending.reservation == nil {
                startupRouter.failExternalOperation(ticket)
                if pendingErase === pending { pendingErase = nil }
            } else {
                startupRouter.suspendErasedSessionCleanup(ticket)
            }
            _ = try? await refreshState(session)
            failure = pendingErase == nil && accessState?.permitsContentAccess == false ? nil : .startup
            throw error
        }
    }

    private func resumeErase(_ pending: PendingErase, access: ProductionAppAccessSessionV1) async throws {
#if DEBUG
        var diagnosticPhase = "original-ownership"
#endif
        do {
            guard pendingErase === pending, let makeService = pending.makeRecoveryService else {
                throw AppAccessContractFailureV1.staleAttempt
            }
#if DEBUG
            diagnosticPhase = "aborted-admission"
#endif
            if let receipt = pending.abortedAdmission {
                try await access.lifecycle.abandonEraseAdmission(receipt)
                try startupRouter.cancelAbortedErase(pending.ticket, receipt: receipt)
                pendingErase = nil
                _ = try await refreshState(access)
                return
            }
#if DEBUG
            diagnosticPhase = "deferred-reconcile"
#endif
            if pending.receipt == nil {
                // Recovery constructs fresh service-local admission state while
                // reusing the original hooks, subject and lifecycle reservation.
                let service = makeService()
                let recovered = try await startupRouter.resumeDeferredErase(pending.ticket) {
                    try await service.reconcileAtStartup(diagnosticsStore: pending.diagnostics)
                }
                if let recovered {
                    pending.session = recovered
                }
            }
#if DEBUG
            diagnosticPhase = "receipt-and-session"
#endif
            guard let receipt = pending.receipt, let erasedSession = pending.session else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
#if DEBUG
            diagnosticPhase = "fresh-binding"
#endif
            if !pending.cleanupActivationRefreshed {
                try await startupRouter.beginErasedSessionActivation(erasedSession,
                    coordinator: pending.coordinator, ticket: pending.ticket)
                pending.cleanupActivationRefreshed = true
            }
            if !pending.adopted {
#if DEBUG
            diagnosticPhase = "replacement-factory"
#endif
                guard let makeReplacement = access.completedEraseReplacement else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
#if DEBUG
            diagnosticPhase = "replacement-construction"
#endif
                let replacement = try makeReplacement(receipt.subject)
#if DEBUG
            diagnosticPhase = "lifecycle-adoption"
#endif
                try await access.lifecycle.adoptCompletedErase(receipt, replacement: replacement)
                pending.adopted = true
            }
            // The router's fresh active startup token controls publication. An
            // inactive/protected-data failure retains adopted completion for retry.
#if DEBUG
            diagnosticPhase = "router-publication"
#endif
            try await startupRouter.finishErasedSessionActivation(erasedSession,
                coordinator: pending.coordinator, ticket: pending.ticket, accessGate: access.gate)
#if DEBUG
            diagnosticPhase = "completion-ownership"
#endif
            guard pendingErase === pending else { throw AppAccessContractFailureV1.staleAttempt }
            pendingErase = nil
            failure = nil
        } catch {
#if DEBUG
            if let observe = eraseRecoveryDiagnosticForTesting {
                let errorType = String(reflecting: type(of: error))
                let policyMismatch = (error as? ProtectedFilePolicyError) == .resourceValueMismatch
                observe("phase=\(diagnosticPhase) type=\(errorType) resourceValueMismatch=\(policyMismatch)")
            }
#endif
            throw error
        }
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
            publishedRoundAccess = nil
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
                publishedRoundAccess = nil
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
        publishedRoundAccess = nil
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
            let backupStore: StoreSessionCoordinator?
            if case let .ready(store, _, _) = startupRouter.route { backupStore = store }
            else { backupStore = nil }
            publishedBackupPreviewAccess = ContentAccess(token: backupToken, surface: .backupImport,
                gate: session.gate, isCurrent: stillCurrent, backupStore: backupStore)
            let renderAccess = ContentAccess(token: token, surface: .render,
                gate: session.gate, isCurrent: stillCurrent, backupStore: backupStore)
            publishedRenderAccess = renderAccess
            publishedReminderSettingsAccess = session.reminderSettingsOwners.map {
                ReminderSettingsAccess(publication: renderAccess, currentOwners: $0)
            }
            if case .ready(let store, _, _) = startupRouter.route {
                publishedSceneNavigationAccess = SceneNavigationAccess(token: sceneToken,
                    isCurrent: stillCurrent, port: session.sceneNavigationStatePort(),
                    router: startupRouter, workspaceID: store.workspaceID, generationID: store.generationID)
                let myDayProvider = store.makeMyDaySourceProvider(accessGate: session.gate)
                publishedMyDayAccess = MyDayAccess(publicationAccess: renderAccess, provider: myDayProvider,
                    planning: store.makeMyDayPlanningCommitService(sourceProvider: myDayProvider))
                if roundReadinessLedger == nil {
                    // This is the first app-lifetime ledger only after the
                    // exact store and render publication have been admitted.
                    // Failure leaves Round unavailable without disturbing the
                    // established app access publication, and a later
                    // eligible publication retries this narrow construction.
                    guard isCurrent(action),
                          action.revision === presentationRevision,
                          contentPublication === publication,
                          sceneIsActive,
                          queuedLifecycleEvents.isEmpty else { return }
                    roundReadinessLedger = try? token.withContentRead(for: .render) {
                        try store.makeRoundReadinessLedger()
                    }
                }
                let draftOrdering = try? token.withContentRead(for: .render) {
                    try store.makeRoundDraftOrderingService(accessGate: session.gate)
                }
                let sessionTransitions = try? token.withContentRead(for: .render) {
                    try store.makeRoundSessionTransitionService(accessGate: session.gate)
                }
                let repetitiveCapture = try? token.withContentRead(for: .render) {
                    guard let sessionTransitions else { throw AppAccessContractFailureV1.accessDenied }
                    return try store.makeRepetitiveCaptureProgressService(transitions: sessionTransitions)
                }
                if let roundReadinessLedger {
                    publishedRoundAccess = RoundAccess(
                        publicationAccess: renderAccess,
                        readinessAuthority: store.makeRoundReadinessAuthority(
                            accessGate: session.gate,
                            ownedStorageLedger: roundReadinessLedger
                        ),
                        draftOrdering: draftOrdering,
                        sessionTransitions: sessionTransitions,
                        repetitiveCapture: repetitiveCapture,
                        itemStore: store
                    )
                } else {
                    publishedRoundAccess = nil
                }
            } else {
                publishedSceneNavigationAccess = nil
                publishedMyDayAccess = nil
                publishedRoundAccess = nil
            }
            permitsContentPresentation = true
        } catch {
            guard isCurrent(action) else { return }
            permitsContentPresentation = false
            publishedMyDayAccess = nil
            publishedRoundAccess = nil
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
            publishedRoundAccess = nil
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
#if DEBUG
        guard !terminatedForTesting else { return }
#endif
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
#if DEBUG
            self.startupActionForTesting = action
            defer {
                if self.startupActionForTesting === action { self.startupActionForTesting = nil }
            }
#endif
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

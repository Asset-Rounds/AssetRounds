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

    private func reportEraseRecoveryForTesting(_ phase: String, error: Error? = nil) {
        let category: String
        switch error {
        case nil: category = "none"
        case is AppAccessContractFailureV1: category = "app-access"
        case is EraseAllServiceError: category = "erase-service"
        case is ProtectedFilePolicyError: category = "file-policy"
        default: category = "other"
        }
        eraseRecoveryDiagnosticForTesting?("phase=\(phase) category=\(category)")
    }
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
        var coordinator: StoreSessionCoordinator?
        let operation: EraseRouterOperationV1
        let diagnostics: DiagnosticsStore
        var makeRecoveryService: (@MainActor () -> EraseAllService)?
        var session: StoreGenerationSession?
        var receipt: CompletedEraseReceiptV1?
        var abortedAdmission: AbortedEraseAdmissionReceiptV1?
        var reservation: AppAccessGateV1.EraseAdoptionToken?
        var adopted = false
        var cleanupActivationRefreshed = false
        var activationFailed = false
#if DEBUG
        var originalServiceForShutdown: EraseAllService?
        var originalShutdownRequested = false
        var completedAbortExpectedFault: EraseAllFailurePoint?
        enum CompletedAbortShutdownState: Equatable {
            case ordinary, poisonedPreRelease, abandoning, abandoned
            case transferring, released, retainedUncertain
        }
        var completedAbortShutdownState = CompletedAbortShutdownState.ordinary
#endif

        init(ticket: StartupRouter.OriginalOperationTicket,
             coordinator: StoreSessionCoordinator, operation: EraseRouterOperationV1,
             diagnostics: DiagnosticsStore) {
            self.ticket = ticket
            self.coordinator = coordinator
            self.operation = operation
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
    private var eraseContinuationTask: Task<Void, Never>?
#if DEBUG
    private var terminatedForTesting = false
    private var startupActionForTesting: Action?

    /// Test teardown must join this owner's tasks, not infer drain from a
    /// covered/checking route. Hard revocation remains the real authority.
    func terminateAndDrainForTesting() async -> Bool {
        // These handles do not own callers executing restore/unlock/erase.
        // Capture that limitation before termination clears activeAction.
        let hasUnjoinedAction = pendingErase != nil || pendingRestoreTransitionID != nil
            || (activeAction != nil && activeAction !== startupActionForTesting)
        terminatedForTesting = true
        receive(.termination)
        let bootstrap = bootstrapTask
        let startup = startupTask
        let eraseContinuation = eraseContinuationTask
        eraseContinuation?.cancel()
        bootstrap?.cancel()
        lifecycleDrainTask?.cancel()
        startup?.cancel()
        await bootstrap?.value
        // Bootstrap can schedule the lifecycle drain before its task exits.
        let lifecycle = lifecycleDrainTask
        lifecycle?.cancel()
        await lifecycle?.value
        await startup?.value
        await eraseContinuation?.value
        let trailingLifecycle = lifecycleDrainTask
        trailingLifecycle?.cancel()
        await trailingLifecycle?.value
        // Retry only the router's existing exact-owner cleanup after all task
        // frames have returned; callers never release an arbitrary writer.
        startupRouter.pauseForAppAccess(discardPrepared: true)
        return !hasUnjoinedAction && pendingErase == nil && pendingRestoreTransitionID == nil && startupActionForTesting == nil
            && bootstrapTask == nil && lifecycleDrainTask == nil && startupTask == nil && eraseContinuationTask == nil
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
    @Published private(set) var pendingRestoreTransitionID: UUID?
    private var pendingRestoreRetryTask: Task<Void, Never>?
#if DEBUG
    private var originalEraseFrameActive = false
    private var expectedCompletedAbortColdFaultForTesting: EraseAllFailurePoint?
    private final class OriginalEraseShutdownAppPin {
        let owner: AppAccessPresentationV1
        let pending: PendingErase
        let session: ProductionAppAccessSessionV1
        var gate: AppAccessGateV1 { session.gate }
        var lifecycle: AppLockLifecycleCoordinatorV1 { session.lifecycle }
        init(owner: AppAccessPresentationV1, pending: PendingErase,
             session: ProductionAppAccessSessionV1) {
            self.owner = owner; self.pending = pending; self.session = session
        }
    }
    private static var retainedOriginalEraseAppShellsForTesting: [OriginalEraseShutdownAppPin] = []

    func requireOriginalEraseOperationAttachmentForTesting(
        _ operation: EraseRouterOperationV1
    ) throws {
        guard let pending = pendingErase, pending.operation === operation,
              originalEraseFrameActive, activeAction != nil,
              !pending.originalShutdownRequested else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    func requirePostRetiredOriginalEraseFenceForTesting(
        operation: EraseRouterOperationV1,
        originalService: EraseAllService
    ) throws {
        guard let pending = pendingErase, pending.operation === operation,
              pending.originalServiceForShutdown === originalService,
              pending.originalShutdownRequested, terminatedForTesting,
              !originalEraseFrameActive, activeAction == nil,
              bootstrapTask == nil, startupTask == nil,
              lifecycleDrainTask == nil, eraseContinuationTask == nil,
              pending.receipt == nil, pending.abortedAdmission == nil,
              pending.reservation != nil, pending.coordinator == nil,
              pending.session == nil, pending.makeRecoveryService == nil,
              !permitsContentPresentation,
              publishedMyDayAccess == nil, publishedRoundAccess == nil,
              let session,
              Self.retainedOriginalEraseAppShellsForTesting.contains(where: {
                  $0.owner === self && $0.pending === pending
                    && $0.gate === session.gate
                    && $0.lifecycle === session.lifecycle
              }) else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    func expectCompletedAbortColdRestartForTesting(
        _ point: EraseAllFailurePoint
    ) throws {
        guard !originalEraseFrameActive, pendingErase == nil,
              expectedCompletedAbortColdFaultForTesting == nil,
              point == .afterEmptyGenerationDirectoryCreate
                || point == .beforePreparedWrite else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        expectedCompletedAbortColdFaultForTesting = point
    }

    /// Completes only the checked old-owner process boundary after the real
    /// abort receipt and one successful lifecycle abandonment.
    func continueCompletedAbortColdRestartForTesting()
        async throws -> EraseRouterOperationV1 {
        guard !originalEraseFrameActive, activeAction == nil,
              let pending = pendingErase,
              pending.completedAbortShutdownState == .abandoned,
              pending.originalShutdownRequested,
              let receipt = pending.abortedAdmission,
              eraseContinuationTask == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        pending.completedAbortShutdownState = .transferring
        do {
            let bootstrap = bootstrapTask
            let startup = startupTask
            let lifecycle = lifecycleDrainTask
            bootstrap?.cancel(); startup?.cancel(); lifecycle?.cancel()
            await bootstrap?.value
            await startup?.value
            await lifecycle?.value
            let trailingLifecycle = lifecycleDrainTask
            trailingLifecycle?.cancel()
            await trailingLifecycle?.value
            guard pendingErase === pending, !originalEraseFrameActive,
                  bootstrapTask == nil, startupTask == nil,
                  lifecycleDrainTask == nil, eraseContinuationTask == nil,
                  startupActionForTesting == nil else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            try await startupRouter.continueCompletedAbortColdRestartForTesting(
                pending.operation, receipt: receipt)
            guard pendingErase === pending,
                  let coordinator = pending.coordinator,
                  pending.session == nil,
                  pending.completedAbortShutdownState == .transferring else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            // Seal the exact original snapshot synchronously under retained
            // EX/G before dropping these pending source aliases. Other held
            // aliases still have to pass the later weak-drain check.
            try startupRouter.sealCompletedAbortSourceBeforeAliasReleaseForTesting(
                pending.operation, receipt: receipt,
                coordinator: coordinator)
            pending.coordinator = nil
            pending.session = nil
            pending.makeRecoveryService = nil
            return pending.operation
        } catch {
            pending.completedAbortShutdownState = .retainedUncertain
            throw error
        }
    }

    func finishCompletedAbortColdRestartForTesting(
        _ operation: EraseRouterOperationV1
    ) throws {
        guard let pending = pendingErase,
              pending.completedAbortShutdownState == .transferring,
              pending.operation === operation,
              let receipt = pending.abortedAdmission,
              pending.coordinator == nil, pending.session == nil,
              pending.makeRecoveryService == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        do {
            try startupRouter.finishCompletedAbortColdRestartForTesting(
                operation, receipt: receipt)
            pending.completedAbortShutdownState = .released
            pendingErase = nil
        } catch {
            pending.completedAbortShutdownState = .retainedUncertain
            throw error
        }
    }

    /// Exact post-retirement fault boundary. The original AppAccess task and
    /// Service frame must have returned; this has no await across EX release.
    func abandonInterruptedPostRetiredEraseForColdRestartForTesting()
        throws -> EraseRouterOperationV1 {
        guard !originalEraseFrameActive, activeAction == nil,
              bootstrapTask == nil, lifecycleDrainTask == nil,
              startupTask == nil, eraseContinuationTask == nil,
              let pending = pendingErase, pending.operation.detached,
              pending.receipt == nil, pending.abortedAdmission == nil,
              pending.reservation != nil, pending.coordinator == nil,
              pending.session == nil, pending.makeRecoveryService == nil,
              let originalService = pending.originalServiceForShutdown,
              !pending.originalShutdownRequested,
              let session else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        Self.retainedOriginalEraseAppShellsForTesting.append(
            OriginalEraseShutdownAppPin(owner: self, pending: pending, session: session))
        pending.originalShutdownRequested = true
        terminatedForTesting = true
        permitsContentPresentation = false
        publishedMyDayAccess = nil
        publishedRoundAccess = nil
        try startupRouter.abandonInterruptedPostRetiredEraseForColdRestartForTesting(
            pending.operation, originalService: originalService)
        return pending.operation
    }

    /// Preserve the actual detached Erase/EX while an external test-held
    /// source context is released. No cold retry is possible until finish
    /// validates the original source and checked-closes the original EX.
    func beginPristinePreparedEraseColdRestartForTesting()
        throws -> EraseRouterOperationV1 {
        guard !originalEraseFrameActive, activeAction == nil,
              bootstrapTask == nil, lifecycleDrainTask == nil,
              startupTask == nil, eraseContinuationTask == nil,
              let pending = pendingErase, pending.operation.detached,
              pending.receipt == nil, pending.abortedAdmission == nil,
              let reservation = pending.reservation,
              pending.coordinator == nil, pending.session == nil,
              pending.makeRecoveryService == nil,
              let service = pending.originalServiceForShutdown,
              !pending.originalShutdownRequested,
              let session else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try service.requirePristineOriginalPreparedColdExitForTesting(
            operation: pending.operation,
            subject: reservation.subject, reservation: reservation)
        Self.retainedOriginalEraseAppShellsForTesting.append(
            OriginalEraseShutdownAppPin(
                owner: self, pending: pending, session: session))
        pending.originalShutdownRequested = true
        terminatedForTesting = true
        permitsContentPresentation = false
        publishedMyDayAccess = nil
        publishedRoundAccess = nil
        try startupRouter.beginPristinePreparedEraseColdRestartForTesting(
            pending.operation, originalService: service)
        return pending.operation
    }

    func finishPristinePreparedEraseColdRestartForTesting(
        _ operation: EraseRouterOperationV1
    ) async throws {
        guard !originalEraseFrameActive,
              let pending = pendingErase,
              pending.operation === operation,
              pending.originalShutdownRequested,
              let reservation = pending.reservation,
              pending.receipt == nil, pending.abortedAdmission == nil,
              pending.coordinator == nil, pending.session == nil,
              pending.makeRecoveryService == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try await startupRouter.finishPristinePreparedEraseColdRestartForTesting(
            operation, subject: reservation.subject,
            reservation: reservation)
    }

    /// The external original Erase frame must already have returned. Router
    /// poison occurs before its first suspension; AppAccess then joins its
    /// own continuation tasks before dropping model aliases.
    func beginInterruptedEarlyEraseColdRestartForTesting(
        expectedFault: EraseAllFailurePoint
    ) async throws -> EraseRouterOperationV1 {
        try await beginOriginalPreparingEraseColdRestartForTesting(
            expectedFault: expectedFault)
    }

    func beginNotificationRefusalEraseColdRestartForTesting()
        async throws -> EraseRouterOperationV1 {
        try await beginOriginalPreparingEraseColdRestartForTesting(
            expectedFault: nil)
    }

    private func beginOriginalPreparingEraseColdRestartForTesting(
        expectedFault: EraseAllFailurePoint?
    ) async throws -> EraseRouterOperationV1 {
        guard !originalEraseFrameActive, activeAction == nil,
              eraseContinuationTask == nil,
              let pending = pendingErase, pending.abortedAdmission == nil,
              let session,
              let service = pending.originalServiceForShutdown,
              !pending.originalShutdownRequested else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        if let expectedFault {
            try service.requireInterruptedOriginalPreparationFaultForTesting(
                expectedFault, operation: pending.operation)
        }
        pending.originalShutdownRequested = true
        Self.retainedOriginalEraseAppShellsForTesting.append(
            OriginalEraseShutdownAppPin(owner: self, pending: pending, session: session))
        terminatedForTesting = true
        if let expectedFault {
            try await startupRouter.beginInterruptedEarlyEraseColdRestartForTesting(
                pending.operation, originalService: service,
                expectedFault: expectedFault)
        } else {
            try await startupRouter.beginNotificationRefusalEraseColdRestartForTesting(
                pending.operation, originalService: service)
        }
        let bootstrap = bootstrapTask
        let startup = startupTask
        let continuation = eraseContinuationTask
        bootstrap?.cancel(); startup?.cancel(); continuation?.cancel()
        await bootstrap?.value
        let lifecycle = lifecycleDrainTask
        lifecycle?.cancel()
        await lifecycle?.value
        await startup?.value
        await continuation?.value
        let trailingLifecycle = lifecycleDrainTask
        trailingLifecycle?.cancel()
        await trailingLifecycle?.value
        guard !originalEraseFrameActive, pendingErase === pending,
              bootstrapTask == nil, startupTask == nil,
              lifecycleDrainTask == nil, eraseContinuationTask == nil,
              startupActionForTesting == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        pending.coordinator = nil
        pending.session = nil
        pending.makeRecoveryService = nil
        return pending.operation
    }
#endif

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
#if DEBUG
        reportEraseRecoveryForTesting("retry.enter")
#endif
        await bootstrapIfNeeded()
        guard let session, sceneIsActive else {
#if DEBUG
            reportEraseRecoveryForTesting("retry.no-session-or-inactive")
#endif
            return
        }
        if pendingRestoreTransitionID != nil {
#if DEBUG
            reportEraseRecoveryForTesting("retry.restore-pending")
#endif
            await retryPendingRestoreTransition()
            schedulePendingRestoreRetryWindow()
            return
        }
        if let pendingErase {
            guard let action = beginLongAction(resumesAfterInactive: true) else {
#if DEBUG
                reportEraseRecoveryForTesting("retry.erase-action-busy")
#endif
                return
            }
            defer { finishLongAction(action) }
            do {
#if DEBUG
                reportEraseRecoveryForTesting("retry.erase-resume-begin")
#endif
                try await resumeErase(pendingErase, access: session)
#if DEBUG
                reportEraseRecoveryForTesting(self.pendingErase == nil
                    ? "retry.erase-resume-cleared" : "retry.erase-resume-pending")
#endif
                if isCurrent(action), self.pendingErase == nil {
                    failure = nil
                    await startAndPublish(session, action: action)
#if DEBUG
                    reportEraseRecoveryForTesting("retry.erase-publish-return")
#endif
                }
            } catch {
#if DEBUG
                reportEraseRecoveryForTesting("retry.erase-catch", error: error)
#endif
                permitsContentPresentation = false
                publishedMyDayAccess = nil
                publishedRoundAccess = nil
                failure = .startup
            }
            return
        }
        let state = await session.gate.currentState()
        guard state.permitsContentAccess else {
#if DEBUG
            reportEraseRecoveryForTesting("retry.no-erase-gate-denied")
#endif
            failure = .startup
            return
        }
        guard let action = beginLongAction(resumesAfterInactive: true) else {
#if DEBUG
            reportEraseRecoveryForTesting("retry.no-erase-action-busy")
#endif
            return
        }
        defer { finishLongAction(action) }
        failure = nil
#if DEBUG
        reportEraseRecoveryForTesting("retry.no-erase-publish-begin")
#endif
        await startAndPublish(session, action: action, retriesStartup: true)
#if DEBUG
        reportEraseRecoveryForTesting("retry.no-erase-publish-return")
#endif
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
              pendingRestoreTransitionID == nil,
              let action = beginLongAction(resumesAfterInactive: false) else {
            throw AppAccessContractFailureV1.accessDenied
        }
        defer { finishLongAction(action) }
        let ticket = try await startupRouter.beginRestoreOperation(
            sourceModelContext: sourceModelContext, sourceGenerationID: sourceGenerationID,
            coordinator: coordinator, validatedPackage: package,
            accessGate: session.gate)
        do {
            guard isCurrent(action), sceneIsActive else {
                throw AppAccessContractFailureV1.accessDenied
            }
            permitsContentPresentation = false
            // The admitted Restore covers this publication. Drop internal
            // capabilities so only genuine external owners delay A's drain.
            contentPublication = nil
            publishedBackupPreviewAccess = nil
            publishedRenderAccess = nil
            publishedSceneNavigationAccess = nil
            publishedReminderSettingsAccess = nil
            publishedMyDayAccess = nil
            publishedRoundAccess = nil
            let restored = try await restoreServiceFactory(applicationSupportURL)
                .restore(validatedPackage: package, currentModelContext: sourceModelContext,
                    currentGenerationID: sourceGenerationID,
                    currentGenerationRootURL: sourceGenerationRootURL, mode: mode,
                    validateAccess: { try await self.startupRouter.validateRestoreOperation(ticket) },
                    attestPublishedPointer: { original, target in
                        try self.startupRouter.attestRestorePublishedPointer(
                            originalCanonicalPointer: original,
                            targetCanonicalPointer: target, ticket: ticket)
                    })
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_PRESENTATION_BOUNDARY_V1 stage=service-returned\n".utf8))
#endif
            let id = try await startupRouter.activateRestoredSession(
                restored, coordinator: coordinator, ticket: ticket)
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_PRESENTATION_BOUNDARY_V1 stage=router-activated\n".utf8))
#endif
            pendingRestoreTransitionID = id
            failure = nil
            schedulePendingRestoreRetryWindow()
            // The sheet's Task and the old ready/maintenance host still own
            // the A context. Return before attempting the weak alias drain.
        } catch {
            if pendingRestoreTransitionID == nil {
                startupRouter.failExternalOperation(ticket)
            }
            if isCurrent(action) { failure = .startup }
            throw error
        }
    }

    /// The sheet/host/scene merely request another exact-ID attempt. Router
    /// proves the old SwiftData aliases drained before releasing A's reader.
    func retryPendingRestoreTransition() async {
#if DEBUG
        let retryEntry: String
        if pendingRestoreTransitionID == nil { retryEntry = "no-pending" }
        else if session == nil { retryEntry = "no-session" }
        else if !sceneIsActive { retryEntry = "inactive-scene" }
        else if activeAction != nil { retryEntry = "action-busy" }
        else { retryEntry = "eligible" }
        FileHandle.standardError.write(Data(
            "V23_RESTORE_RETRY_ENTRY_V1 first=\(retryEntry)\n".utf8))
#endif
        guard let id = pendingRestoreTransitionID,
              let session, sceneIsActive,
              let action = beginLongAction(resumesAfterInactive: true) else { return }
        defer { finishLongAction(action) }
        do {
            guard try await startupRouter.resumeOriginalRestoreReaderTransition(id) else {
#if DEBUG
                FileHandle.standardError.write(Data(
                    "V23_RESTORE_RETRY_ENTRY_V1 result=router-pending\n".utf8))
#endif
                return
            }
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_RETRY_ENTRY_V1 result=router-complete\n".utf8))
#endif
            guard pendingRestoreTransitionID == id else { return }
            pendingRestoreTransitionID = nil
            failure = nil
            if isCurrent(action), sceneIsActive {
                await startAndPublish(session, action: action)
            }
        } catch {
#if DEBUG
            FileHandle.standardError.write(Data(
                "V23_RESTORE_RETRY_ENTRY_V1 result=router-threw\n".utf8))
#endif
            failure = .startup
            permitsContentPresentation = false
            publishedMyDayAccess = nil
            publishedRoundAccess = nil
        }
    }

    /// A bounded liveness window for SwiftUI's asynchronous sheet teardown.
    /// Time never grants authority: every attempt still asks Router to prove
    /// the exact weak alias drain and checked A release. Later scene/retry
    /// events can start another finite window if the host held A longer.
    private func schedulePendingRestoreRetryWindow() {
        guard pendingRestoreRetryTask == nil,
              let id = pendingRestoreTransitionID else { return }
        pendingRestoreRetryTask = Task { @MainActor [weak self] in
            defer { self?.pendingRestoreRetryTask = nil }
            for _ in 0..<30 {
                guard let self, self.pendingRestoreTransitionID == id,
                      self.failure == nil else { return }
                await self.retryPendingRestoreTransition()
                guard self.pendingRestoreTransitionID == id else { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func requestPendingRestoreTransitionRetry() {
        schedulePendingRestoreRetryWindow()
    }

    func performErase(
        applicationSupportURL: URL,
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore
    ) async throws {
#if DEBUG
        guard !originalEraseFrameActive else { throw AppAccessContractFailureV1.staleAttempt }
        let completedAbortColdFault = expectedCompletedAbortColdFaultForTesting
        expectedCompletedAbortColdFaultForTesting = nil
        originalEraseFrameActive = true
        defer { originalEraseFrameActive = false }
#endif
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
        let retirementOperation = try startupRouter.eraseRetirementOperation(for: ticket)
        let pending = PendingErase(ticket: ticket, coordinator: coordinator,
            operation: retirementOperation, diagnostics: diagnosticsStore)
#if DEBUG
        pending.completedAbortExpectedFault = completedAbortColdFault
#endif
        pendingErase = pending
#if DEBUG
        do {
            try retirementOperation.attachAppAccessForTesting(self)
        } catch {
            pendingErase = nil
            startupRouter.failExternalOperation(ticket)
            throw error
        }
#endif
        permitsContentPresentation = false
        // The covered publication is no longer an internal source owner.
        // Externally held capabilities remain live aliases and still block
        // the checked original-reader drain until their callers release them.
        contentPublication = nil
        publishedBackupPreviewAccess = nil
        publishedRenderAccess = nil
        publishedSceneNavigationAccess = nil
        publishedReminderSettingsAccess = nil
        publishedMyDayAccess = nil
        publishedRoundAccess = nil
        failure = nil
        let admission: EraseAdmission = { [weak self, weak pending] subject in
            guard let self, let pending, self.pendingErase === pending else {
                throw AppAccessContractFailureV1.staleAttempt
            }
#if DEBUG
            guard !pending.originalShutdownRequested else { throw AppAccessContractFailureV1.staleAttempt }
#endif
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
#if DEBUG
            guard !pending.originalShutdownRequested else { return }
#endif
            // Synchronous and independent of presentation epochs: physical
            // completion is retained even if the scene became inactive.
            if pending.receipt == nil { pending.receipt = receipt }
        }
        let aborted: EraseAbort = { [weak self, weak pending] receipt in
            guard let self, let pending, self.pendingErase === pending else { return }
#if DEBUG
            guard !pending.originalShutdownRequested else { return }
#endif
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
        do {
            let service = try startupRouter.configureEraseService(makeService(), operation: retirementOperation)
#if DEBUG
            pending.originalServiceForShutdown = service
            if let completedAbortColdFault {
                try service.expectCompletedAbortColdShutdownForTesting(
                    completedAbortColdFault, operation: retirementOperation)
            }
#endif
            let dependencies = try coordinator.packageLifecycleDependencies()
            let outcome = try await service.erase(confirmation: confirmation,
                coordinator: coordinator, diagnosticsStore: diagnosticsStore,
                operation: retirementOperation,
                activate: { [weak self, weak pending] erased in
                    guard let self, let pending, self.pendingErase === pending else { return }
#if DEBUG
                    guard !pending.originalShutdownRequested else { return }
#endif
                    pending.session = erased
                    do {
                        try self.startupRouter.activateErasePreparationSession(
                            erased, coordinator: coordinator, operation: pending.operation)
                    } catch { pending.activationFailed = true }
                }, lifecycleDependencies: dependencies)
            guard outcome.operation === retirementOperation, retirementOperation.detached,
                  !pending.activationFailed else { throw AppAccessContractFailureV1.staleAttempt }
            releaseDetachedEraseAliases(pending)
            scheduleEraseContinuation(pending)
            // The queued continuation observes actual weak drain after this
            // service/callback/argument frame has returned; scheduling itself
            // is never accepted as a drain proof.
            return
        } catch {
            let originalError = error
            // Keep the actual cleanup ticket and any authentic receipt for a
            // retry. A retry never starts another physical Erase operation.
            permitsContentPresentation = false
            publishedMyDayAccess = nil
            publishedRoundAccess = nil
#if DEBUG
            // Fixed phase labels only; each existing proof is evaluated once
            // in its original short-circuit position.
            func recordCompletedAbortPhase(_ phase: String) {
                FileHandle.standardError.write(Data((
                    "ERASE_COMPLETED_ABORT_PHASE_V1 phase=\(phase)\n"
                ).utf8))
            }
            var serviceProofPassed = false
            var resourceProofPassed = false
            if let expectedFault = pending.completedAbortExpectedFault,
               let receipt = pending.abortedAdmission,
               let originalService = pending.originalServiceForShutdown,
               pending.reservation == receipt.reservation,
               pending.receipt == nil,
               !pending.originalShutdownRequested,
               ({ () -> Bool in
                    serviceProofPassed = (try? originalService
                        .requireCompletedAbortColdShutdownForTesting(
                            expectedFault, operation: pending.operation,
                            receipt: receipt)) != nil
                    return serviceProofPassed
               }()),
               ({ () -> Bool in
                    resourceProofPassed = (try? startupRouter
                        .requireEraseAbortResourcesSettled(pending.operation)) != nil
                    return resourceProofPassed
               }()) {
                recordCompletedAbortPhase("eligible")
                // Every owner is pinned before the first new descriptor probe.
                Self.retainedOriginalEraseAppShellsForTesting.append(
                    OriginalEraseShutdownAppPin(owner: self, pending: pending, session: session))
                pending.originalShutdownRequested = true
                terminatedForTesting = true
                pending.completedAbortShutdownState = .poisonedPreRelease
                var shutdownPhase = "router-poison"
                do {
                    try startupRouter.poisonCompletedAbortColdRestartForTesting(
                        pending.operation, service: originalService,
                        receipt: receipt, expectedFault: expectedFault)
                    shutdownPhase = "no-effect"
                    try originalService.requireCompletedAbortNoEffectForTesting(
                        operation: pending.operation, receipt: receipt)
                    pending.completedAbortShutdownState = .abandoning
                    shutdownPhase = "lifecycle-abandon"
                    try await session.lifecycle.abandonEraseAdmission(receipt)
                    shutdownPhase = "post-lifecycle-binding"
                    guard pendingErase === pending,
                          pending.abortedAdmission?.matchesExactOriginalAuthority(receipt) == true,
                          pending.originalServiceForShutdown === originalService,
                          self.session?.gate === session.gate,
                          self.session?.lifecycle === session.lifecycle else {
                        throw AppAccessContractFailureV1.staleAttempt
                    }
                    shutdownPhase = "router-lifecycle-release"
                    try startupRouter.markCompletedAbortLifecycleReleasedForTesting(
                        pending.operation, receipt: receipt)
                    pending.completedAbortShutdownState = .abandoned
                    recordCompletedAbortPhase("abandoned")
                } catch {
                    recordCompletedAbortPhase(shutdownPhase)
                    pending.completedAbortShutdownState = .retainedUncertain
                }
                failure = .startup
                throw originalError
            }
            let deniedPhase: String
            if pending.completedAbortExpectedFault == nil {
                deniedPhase = "no-expected-fault"
            } else if pending.abortedAdmission == nil {
                deniedPhase = "no-abort-receipt"
            } else if pending.originalServiceForShutdown == nil {
                deniedPhase = "no-original-service"
            } else if pending.reservation != pending.abortedAdmission?.reservation {
                deniedPhase = "reservation-mismatch"
            } else if pending.receipt != nil {
                deniedPhase = "completion-present"
            } else if pending.originalShutdownRequested {
                deniedPhase = "already-shutting-down"
            } else if !serviceProofPassed {
                deniedPhase = "service-proof"
            } else if !resourceProofPassed {
                deniedPhase = "resource-proof"
            } else {
                deniedPhase = "unknown"
            }
            recordCompletedAbortPhase(deniedPhase)
#endif
            if let receipt = pending.abortedAdmission {
                do {
                    try startupRouter.requireEraseAbortResourcesSettled(pending.operation)
                    try await session.lifecycle.abandonEraseAdmission(receipt)
                    try startupRouter.cancelAbortedErase(pending.ticket, receipt: receipt)
                    if pendingErase === pending { pendingErase = nil }
                } catch { /* An unaccepted abort proof remains owned for retry. */ }
            } else if pending.reservation == nil {
                do {
                    try startupRouter.cancelUnadmittedErase(ticket)
                    if pendingErase === pending { pendingErase = nil }
                } catch {
                    startupRouter.suspendErasedSessionCleanup(ticket)
                }
            } else {
                startupRouter.suspendErasedSessionCleanup(ticket)
            }
            _ = try? await refreshState(session)
            failure = pendingErase == nil && accessState?.permitsContentAccess == false ? nil : .startup
            throw error
        }
    }

    private func releaseDetachedEraseAliases(_ pending: PendingErase) {
        guard pendingErase === pending, pending.operation.detached else { return }
        pending.coordinator = nil
        pending.session = nil
        pending.makeRecoveryService = nil
        pending.activationFailed = false
    }

    private func scheduleEraseContinuation(_ pending: PendingErase) {
#if DEBUG
        guard !pending.originalShutdownRequested else {
            reportEraseRecoveryForTesting("continuation.original-shutdown")
            return
        }
#endif
        guard eraseContinuationTask == nil, pendingErase === pending else {
#if DEBUG
            reportEraseRecoveryForTesting("continuation.already-running-or-stale")
#endif
            return
        }
#if DEBUG
        reportEraseRecoveryForTesting("continuation.scheduled")
#endif
        eraseContinuationTask = Task { @MainActor [weak self, weak pending] in
            guard let self else { return }
            var followsCompletedDetach = false
            defer {
                self.eraseContinuationTask = nil
                if followsCompletedDetach, let pending, self.pendingErase === pending {
                    self.scheduleEraseContinuation(pending)
                }
            }
            guard let pending, self.pendingErase === pending, let access = self.session else {
#if DEBUG
                self.reportEraseRecoveryForTesting("continuation.owner-unavailable")
#endif
                return
            }
            guard self.activeAction == nil,
                  let action = self.beginLongAction(resumesAfterInactive: true) else {
#if DEBUG
                self.reportEraseRecoveryForTesting("continuation.action-busy")
#endif
                return
            }
            defer { self.finishLongAction(action) }
            let wasDetached = pending.operation.detached
            do {
#if DEBUG
                self.reportEraseRecoveryForTesting("continuation.resume-begin")
#endif
                try await self.resumeErase(pending, access: access)
#if DEBUG
                self.reportEraseRecoveryForTesting(self.pendingErase == nil
                    ? "continuation.resume-cleared" : "continuation.resume-pending")
#endif
                followsCompletedDetach = !wasDetached && pending.operation.detached
                if self.pendingErase == nil, self.sceneIsActive, self.isCurrent(action) {
#if DEBUG
                    self.reportEraseRecoveryForTesting("continuation.publish-begin")
#endif
                    await self.startAndPublish(access, action: action)
#if DEBUG
                    self.reportEraseRecoveryForTesting("continuation.publish-return")
#endif
                }
            } catch {
#if DEBUG
                self.reportEraseRecoveryForTesting("continuation.catch", error: error)
#endif
                self.permitsContentPresentation = false
                self.publishedMyDayAccess = nil
                self.publishedRoundAccess = nil
                self.failure = .startup
            }
        }
    }

    private func resumeErase(_ pending: PendingErase, access: ProductionAppAccessSessionV1) async throws {
#if DEBUG
        var diagnosticPhase = "original-ownership"
#endif
        do {
            guard pendingErase === pending else { throw AppAccessContractFailureV1.staleAttempt }
#if DEBUG
            guard !pending.originalShutdownRequested else { throw AppAccessContractFailureV1.staleAttempt }
#endif
            if let receipt = pending.abortedAdmission {
                // Actual transient-reader disposal/rollback precedes this
                // authentic no-effect receipt; no reservation is abandoned
                // merely because a constructor threw.
                try startupRouter.requireEraseAbortResourcesSettled(pending.operation)
                try await access.lifecycle.abandonEraseAdmission(receipt)
                try startupRouter.cancelAbortedErase(pending.ticket, receipt: receipt)
                pendingErase = nil
                _ = try await refreshState(access)
                return
            }
            if !pending.operation.detached {
#if DEBUG
                diagnosticPhase = "original-preparation"
#endif
                guard let coordinator = pending.coordinator, let makeService = pending.makeRecoveryService else {
                    throw AppAccessContractFailureV1.staleAttempt
                }
#if DEBUG
                diagnosticPhase = "original-owner-resume"
#endif
                try startupRouter.resumeOriginalErasePreparation(pending.operation, coordinator: coordinator)
                if pending.operation.hasPreparedCleanup {
#if DEBUG
                    diagnosticPhase = "original-prepared-detach"
#endif
                    try await pending.operation.detach(coordinator: coordinator)
                } else {
#if DEBUG
                    diagnosticPhase = "original-service-configuration"
#endif
                    let service = try startupRouter.configureEraseService(makeService(), operation: pending.operation)
#if DEBUG
                    pending.originalServiceForShutdown = service
#endif
#if DEBUG
                    diagnosticPhase = "original-service-reconcile"
#endif
                    _ = try await service.reconcileForOriginalErase(diagnosticsStore: pending.diagnostics,
                        coordinator: coordinator, operation: pending.operation) { [weak self, weak pending] recovered in
                        guard let self, let pending, self.pendingErase === pending else { return }
#if DEBUG
                        guard !pending.originalShutdownRequested else { return }
#endif
                        do {
                            try self.startupRouter.activateErasePreparationSession(recovered,
                                coordinator: coordinator, operation: pending.operation)
                        } catch { pending.activationFailed = true }
                    }
                }
#if DEBUG
                diagnosticPhase = "original-detachment-result"
#endif
                guard pending.operation.detached, !pending.activationFailed else {
                    throw AppAccessContractFailureV1.staleAttempt
                }
                releaseDetachedEraseAliases(pending)
                scheduleEraseContinuation(pending)
                return
            }
#if DEBUG
            diagnosticPhase = "actual-retirement"
#endif
            if pending.receipt == nil {
                guard try await pending.operation.advanceCleanup() else {
#if DEBUG
                    reportEraseRecoveryForTesting("resume.cleanup-incomplete")
#endif
                    return
                }
                let (_, _, receipt) = try pending.operation.completedRetirement()
                guard let receipt else { throw AppAccessContractFailureV1.configurationUnknown }
                pending.receipt = receipt
            }
            guard let receipt = pending.receipt else { throw AppAccessContractFailureV1.configurationUnknown }
            if !pending.adopted {
#if DEBUG
                diagnosticPhase = "lifecycle-adoption"
#endif
                guard let makeReplacement = access.completedEraseReplacement else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                let replacement = try makeReplacement(receipt.subject)
                try await access.lifecycle.adoptCompletedErase(receipt, replacement: replacement)
                pending.adopted = true
            }
#if DEBUG
            diagnosticPhase = "fresh-construction-and-publication"
#endif
            try await startupRouter.finishRetiredEraseActivation(pending.operation, accessGate: access.gate)
            guard pendingErase === pending else { throw AppAccessContractFailureV1.staleAttempt }
            pendingErase = nil
            failure = nil
#if DEBUG
            reportEraseRecoveryForTesting("resume.fresh-owner-ready")
#endif
        } catch {
#if DEBUG
            reportEraseRecoveryForTesting("resume." + diagnosticPhase, error: error)
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
        if pendingRestoreTransitionID != nil {
            // A scene-active edge is a useful retry after the old host has
            // actually gone away. Time/event delivery itself grants nothing:
            // the Router still checks the exact weak drain and held leases.
            schedulePendingRestoreRetryWindow()
        } else {
            scheduleEligibleStartup(session)
        }
    }

    private func startAndPublish(
        _ session: ProductionAppAccessSessionV1,
        action: Action,
        retriesStartup: Bool = false
    ) async {
#if DEBUG
        reportEraseRecoveryForTesting("publish.begin")
#endif
        guard pendingRestoreTransitionID == nil else {
#if DEBUG
            reportEraseRecoveryForTesting("publish.restore-pending")
#endif
            return
        }
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
            // Router can finish startup by publishing a maintenance route
            // without throwing. Only its actual ready owner may back content.
            guard case .ready = startupRouter.route else {
#if DEBUG
                reportEraseRecoveryForTesting("publish.router-not-ready-first")
#endif
                throw AppAccessContractFailureV1.accessDenied
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
            guard case .ready = startupRouter.route else {
#if DEBUG
                reportEraseRecoveryForTesting("publish.router-not-ready-final")
#endif
                throw AppAccessContractFailureV1.accessDenied
            }
            guard isCurrent(action),
                  action.revision === presentationRevision,
                  sceneIsActive,
                  queuedLifecycleEvents.isEmpty,
                  state.permitsContentAccess else {
                if isCurrent(action), action.resumesAfterInactive {
                    retainPendingStartup(session, action: action)
                }
#if DEBUG
                reportEraseRecoveryForTesting("publish.action-ineligible")
#endif
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
#if DEBUG
            reportEraseRecoveryForTesting("publish.ready")
#endif
        } catch {
#if DEBUG
            reportEraseRecoveryForTesting("publish.catch", error: error)
#endif
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
        guard startupTask == nil, activeAction == nil, pendingErase == nil,
              pendingRestoreTransitionID == nil, queuedLifecycleEvents.isEmpty,
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

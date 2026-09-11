import Foundation

/// Presentation vocabulary only. These values never enter a journal, backup,
/// receipt, or transport. The current app has no remote synchronization evidence.
enum LocalizedSyncStateV1: String, CaseIterable, Sendable {
    case pending, saved, syncing, synchronized, failed, conflicted, recovered
}

enum LocalizedRestoreStateV1: CaseIterable, Sendable {
    case checking, restoring, failed, complete
}

enum LocalizedRemoteSyncStatusV1: CaseIterable, Sendable {
    case syncing, synchronized
}

enum LocalizedSyncStateMessageKeyV1: String, CaseIterable, Sendable {
    case unsavedChanges = "v30.sync-state.unsaved-changes"
    case savingLocally = "v30.sync-state.saving-locally"
    case savedLocally = "v30.sync-state.saved-locally"
    case saveBlocked = "v30.sync-state.save-blocked"
    case committingLocally = "v30.sync-state.committing-locally"
    case draftConflict = "v30.sync-state.draft-conflict"
    case draftRecoveryRequired = "v30.sync-state.draft-recovery-required"
    case committedLocally = "v30.sync-state.committed-locally"
    case discarding = "v30.sync-state.discarding"
    case discarded = "v30.sync-state.discarded"
    case attachmentSelected = "v30.sync-state.attachment-selected"
    case attachmentLoading = "v30.sync-state.attachment-loading"
    case attachmentStaged = "v30.sync-state.attachment-staged"
    case attachmentProcessing = "v30.sync-state.attachment-processing"
    case attachmentReady = "v30.sync-state.attachment-ready"
    case attachmentRetryableFailure = "v30.sync-state.attachment-retryable-failure"
    case attachmentBlocked = "v30.sync-state.attachment-blocked"
    case attachmentRemoving = "v30.sync-state.attachment-removing"
    case attachmentPromoted = "v30.sync-state.attachment-promoted"
    case attachmentProtectedData = "v30.sync-state.attachment-protected-data"
    case attachmentLowStorage = "v30.sync-state.attachment-low-storage"
    case replayPending = "v30.sync-state.replay-pending"
    case replayMissingContent = "v30.sync-state.replay-missing-content"
    case replayConflict = "v30.sync-state.replay-conflict"
    case replayFailed = "v30.sync-state.replay-failed"
    case replayRecovered = "v30.sync-state.replay-recovered"
    case replayNoChanges = "v30.sync-state.replay-no-changes"
    case remoteSyncUnavailable = "v30.sync-state.remote-sync-unavailable"
    case syncingUnavailable = "v30.sync-state.syncing-unavailable"
    case synchronizedUnavailable = "v30.sync-state.synchronized-unavailable"
    case startupChecking = "v30.sync-state.startup-checking"
    case startupReady = "v30.sync-state.startup-ready"
    case eraseCleanupPending = "v30.sync-state.erase-cleanup-pending"
    case maintenanceDataPointer = "v30.sync-state.maintenance-data-pointer"
    case maintenanceDataGeneration = "v30.sync-state.maintenance-data-generation"
    case maintenanceFinalization = "v30.sync-state.maintenance-finalization"
    case maintenanceMedia = "v30.sync-state.maintenance-media"
    case maintenanceRestore = "v30.sync-state.maintenance-restore"
    case maintenanceErase = "v30.sync-state.maintenance-erase"
    case maintenanceFieldDraft = "v30.sync-state.maintenance-field-draft"
    case restoreChecking = "v30.sync-state.restore-checking"
    case restoreInProgress = "v30.sync-state.restore-in-progress"
    case restoreFailed = "v30.sync-state.restore-failed"
    case restoreComplete = "v30.sync-state.restore-complete"
    case recoveryHealthy = "v30.sync-state.recovery-healthy"
    case recoveryChecking = "v30.sync-state.recovery-checking"
    case recoveryActionable = "v30.sync-state.recovery-actionable"
    case recoveryInProgress = "v30.sync-state.recovery-in-progress"
    case recoveryInterrupted = "v30.sync-state.recovery-interrupted"
    case recoveryFileRequired = "v30.sync-state.recovery-file-required"
    case recoveryValidationFailed = "v30.sync-state.recovery-validation-failed"
    case recoveryPartialSafe = "v30.sync-state.recovery-partial-safe"
    case recoveryComplete = "v30.sync-state.recovery-complete"
    case recoveryRestartRequired = "v30.sync-state.recovery-restart-required"
    case recoveryExternalActionRequired = "v30.sync-state.recovery-external-action-required"

    var localizationKey: LocalizationKeyV1 {
        // Closed repository-owned literals; the registry validates every entry.
        try! LocalizationKeyV1(rawValue)
    }
}

/// Rebuildable, non-Codable copy derived from incumbent state. Success is scoped
/// to the local operation named by the message, never delivery to another device.
struct LocalizedSyncStatePresentationV1: Equatable, Sendable {
    let state: LocalizedSyncStateV1?
    let messageKey: LocalizedSyncStateMessageKeyV1
    let permitsSuccessAnnouncement: Bool
    var claimsRemoteSynchronization: Bool { false }

    private init(
        _ state: LocalizedSyncStateV1?, _ key: LocalizedSyncStateMessageKeyV1,
        success: Bool = false
    ) {
        self.state = state
        messageKey = key
        permitsSuccessAnnouncement = success
    }

    /// Call only after the incumbent local receipt has been read back.
    static let savedLocally = Self(.saved, .savedLocally, success: true)
    static let remoteSyncUnavailable = Self(nil, .remoteSyncUnavailable)

    static func remoteStatus(_ requested: LocalizedRemoteSyncStatusV1) -> Self {
        switch requested {
        case .syncing: return Self(nil, .syncingUnavailable)
        case .synchronized: return Self(nil, .synchronizedUnavailable)
        }
    }

    /// The existing durability mapper owns receipt read-back and dirty/in-flight
    /// precedence. Localization does not reinterpret its checkpoint or save it.
    static func draft(_ state: DraftDurabilityPresentationStateV1) -> Self {
        switch state {
        case .unsavedChanges: return Self(.pending, .unsavedChanges)
        case .savingOnThisIPhone: return Self(.pending, .savingLocally)
        case .savedOnThisIPhone: return .savedLocally
        case .saveBlocked: return Self(.failed, .saveBlocked)
        case .committing: return Self(.pending, .committingLocally)
        case .conflicted: return Self(.conflicted, .draftConflict)
        case .recoveryRequired: return Self(.failed, .draftRecoveryRequired)
        case .committed: return Self(.saved, .committedLocally, success: true)
        case .discarding: return Self(.pending, .discarding)
        case .discarded: return Self(nil, .discarded)
        }
    }

    static func attachment(
        _ item: AttachmentStagingItemV1, durableReceiptReadBack: Bool
    ) throws -> Self {
        try item.validate()
        // An operational restriction cannot become a ready announcement merely
        // because an older stage was complete. No attachment bytes are read here.
        switch item.protectionState {
        case .protectedDataUnavailable: return Self(.failed, .attachmentProtectedData)
        case .lowStorage: return Self(.failed, .attachmentLowStorage)
        case .available: break
        }
        return attachment(DraftAttachmentPresentationMapperV1.state(
            for: item, durableReceiptReadBack: durableReceiptReadBack
        ))
    }

    static func attachment(_ state: DraftAttachmentPresentationStateV1) -> Self {
        switch state {
        case .selected: return Self(.pending, .attachmentSelected)
        case .loading: return Self(.pending, .attachmentLoading)
        case .stagedLocal: return Self(.pending, .attachmentStaged)
        case .processing: return Self(.pending, .attachmentProcessing)
        case .ready: return Self(.saved, .attachmentReady, success: true)
        case .retryableFailure: return Self(.failed, .attachmentRetryableFailure)
        case .blocked: return Self(.failed, .attachmentBlocked)
        // The incumbent mapper calls removePending "removed"; it is still pending.
        case .removed: return Self(.pending, .attachmentRemoving)
        case .promoted: return Self(.saved, .attachmentPromoted, success: true)
        }
    }

    static func replay(
        receipt: ChangeReplayReceiptV1, isDeferred: Bool, limits: ChangeJournalLimitsV1
    ) throws -> Self {
        try receipt.validate(limits: limits)
        let dispositions = Set(receipt.dispositions.map(\.disposition))
        if dispositions.contains(.rejected) { return Self(.failed, .replayFailed) }
        if dispositions.contains(.unresolvedConflict) { return Self(.conflicted, .replayConflict) }
        if dispositions.contains(.deferredContent) { return Self(.pending, .replayMissingContent) }
        if isDeferred || dispositions.contains(.deferredGap) { return Self(.pending, .replayPending) }
        guard !dispositions.isEmpty else { return Self(nil, .replayNoChanges) }
        // Only these exact incumbent dispositions finish a local replay. An
        // excluded/rebuild disposition alone is not evidence that data recovered.
        guard dispositions.isSubset(of: [.applied, .alreadyApplied, .deleteWon, .derivedRebuild, .localOnlyExcluded]) else {
            return Self(.failed, .replayFailed)
        }
        guard !dispositions.isDisjoint(with: [.applied, .alreadyApplied, .deleteWon]) else {
            return Self(nil, .replayNoChanges)
        }
        return Self(.recovered, .replayRecovered, success: true)
    }

    static func restore(_ state: LocalizedRestoreStateV1) -> Self {
        switch state {
        case .checking: return Self(.pending, .restoreChecking)
        case .restoring: return Self(.pending, .restoreInProgress)
        case .failed: return Self(.failed, .restoreFailed)
        case .complete: return Self(.recovered, .restoreComplete, success: true)
        }
    }

    static func recovery(_ state: RecoveryCenterStateV1) -> Self {
        switch state {
        case .healthy: return Self(nil, .recoveryHealthy)
        case .checking: return Self(.pending, .recoveryChecking)
        case .actionable: return Self(.failed, .recoveryActionable)
        case .inProgress: return Self(.pending, .recoveryInProgress)
        case .interrupted: return Self(.failed, .recoveryInterrupted)
        case .fileRequired: return Self(.pending, .recoveryFileRequired)
        case .validationFailed: return Self(.failed, .recoveryValidationFailed)
        case .partialSafe: return Self(.pending, .recoveryPartialSafe)
        case .complete: return Self(.recovered, .recoveryComplete, success: true)
        case .restartRequired: return Self(.pending, .recoveryRestartRequired)
        case .externalActionRequired: return Self(.pending, .recoveryExternalActionRequired)
        }
    }
}

import Foundation

enum RecoveryCenterLifecycleAdapterFailureV1: Error, Equatable, Sendable {
    case draftUnavailable
    case draftRecoveryRequired
    case staleDraft
    case invalidExternalEffect
    case operationInProgress
}

/// Device-operational lifecycle binding for C01. The injected store is the
/// existing diagnostics/support actor and the injected scratch port is the
/// existing lease store; this adapter owns neither a file format nor storage.
actor RecoveryCenterLifecycleAdapterV1:
    RecoverySupportExportPreparingV1,
    RecoveryFeedbackHandoffPerformingV1 {
    typealias FeedbackHandoff = @Sendable (
        FeedbackHandoffPreviewV1
    ) async throws -> FeedbackHandoffResultV1

    private let store: any DeviceOperationalSupportStoreV3
    private let supportBuilder: SupportBundleBuilderV1
    private let scratch: any ScratchDataLeasePortV1
    private let feedbackHandoff: FeedbackHandoff
    private var operationInProgress = false

    init(
        store: any DeviceOperationalSupportStoreV3,
        supportBuilder: SupportBundleBuilderV1,
        scratch: any ScratchDataLeasePortV1,
        feedbackHandoff: @escaping FeedbackHandoff
    ) {
        self.store = store
        self.supportBuilder = supportBuilder
        self.scratch = scratch
        self.feedbackHandoff = feedbackHandoff
    }

    func feedbackDraftSnapshot() async throws -> SupportFeedbackDraftStoreSnapshotV1 {
        try await store.supportFeedbackDraftSnapshot()
    }

    /// Returns only the bounded, user-requested local recovery copy. It is not
    /// a support-bundle member and this adapter performs no external effect.
    func feedbackRecoveryCopy() async throws -> Data? {
        try await store.supportFeedbackRecoveryCopy()
    }

    func saveFeedbackDraft(
        _ draft: SupportFeedbackDraftV1,
        expectedRevision: UInt64?
    ) async throws {
        try beginOperation()
        defer { operationInProgress = false }
        try draft.validate()
        try await store.saveSupportFeedbackDraft(draft, expectedRevision: expectedRevision)
    }

    func discardFeedbackDraft(
        expectedDraftID: UUID,
        expectedRevision: UInt64
    ) async throws {
        try beginOperation()
        defer { operationInProgress = false }
        try await store.discardSupportFeedbackDraft(
            expectedDraftID: expectedDraftID,
            expectedRevision: expectedRevision
        )
    }

    func prepareSupportExport(
        mode: SupportBundleModeV1,
        cancellation: SupportExportCancellationV1
    ) async throws -> SupportExportResultV1 {
        try beginOperation()
        defer { operationInProgress = false }
        try await supportBuilder.prepare(mode: mode, cancellation: cancellation)
    }

    func finishSupportExport(
        _ prepared: SupportExportResultV1,
        disposition: SupportExportDispositionV1
    ) async throws -> SupportExportResultV1 {
        try beginOperation()
        defer { operationInProgress = false }
        try await supportBuilder.finish(prepared, disposition: disposition)
    }

    func handoff(_ preview: FeedbackHandoffPreviewV1) async throws -> FeedbackHandoffResultV1 {
        try beginOperation()
        defer { operationInProgress = false }
        let snapshot = try await store.supportFeedbackDraftSnapshot()
        switch snapshot.state {
        case .recoveryRequired:
            throw RecoveryCenterLifecycleAdapterFailureV1.draftRecoveryRequired
        case .empty:
            throw RecoveryCenterLifecycleAdapterFailureV1.draftUnavailable
        case .available:
            guard let draft = snapshot.draft else {
                throw RecoveryCenterLifecycleAdapterFailureV1.draftUnavailable
            }
            do {
                try preview.validate(against: draft)
            } catch {
                throw RecoveryCenterLifecycleAdapterFailureV1.staleDraft
            }
        }

        let result = try await feedbackHandoff(preview)
        guard Self.valid(result: result, for: preview.destination),
              result.preservesDraft,
              !FeedbackHandoffResultV1.claimsDeliveredOrReceived else {
            throw RecoveryCenterLifecycleAdapterFailureV1.invalidExternalEffect
        }
        // Handoff never mutates or silently purges the device-operational draft.
        // Removal is available only through discardFeedbackDraft with exact CAS.
        return result
    }

    func reset() async throws {
        try beginOperation()
        defer { operationInProgress = false }
        // Clean ephemeral support bytes before dropping their persisted reference.
        try await scratch.resetScratchData()
        try await store.resetOperationalSupport()
    }

    func erase() async throws {
        try beginOperation()
        defer { operationInProgress = false }
        try await scratch.eraseScratchData()
        try await store.resetOperationalSupport()
    }

    private func beginOperation() throws {
        guard !operationInProgress else {
            throw RecoveryCenterLifecycleAdapterFailureV1.operationInProgress
        }
        operationInProgress = true
    }

    private static func valid(
        result: FeedbackHandoffResultV1,
        for destination: FeedbackHandoffDestinationV1
    ) -> Bool {
        switch destination {
        case .mail:
            return result == .handedToMail || result == .savedInMail
                || result == .cancelled || result == .failed
        case .localOnly:
            return result == .localOnly || result == .cancelled || result == .failed
        }
    }
}

enum RecoveryCenterLifecycleAdapterBoundaryV1 {
    static let createsSecondStore = false
    static let createsSecondScratchLeaseStore = false
    static let writesWorkspaceTruth = false
    static let includesDraftInBackupOrExport = false
    static let usesNetworkOrAutomaticUpload = false
    static let persistsSecretFieldsOrPassphraseCredentials = false
}

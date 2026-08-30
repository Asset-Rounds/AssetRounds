import Foundation

enum RecoveryCenterCoordinatorFailureV1: Error, Equatable, Sendable {
    case conflictingAuthorityInput
    case invalidSupportResult
    case divergentFeedbackHandoff
}

protocol RecoverySupportExportPreparingV1: Sendable {
    func prepareSupportExport(mode: SupportBundleModeV1, cancellation: SupportExportCancellationV1) async throws -> SupportExportResultV1
}

protocol RecoveryFeedbackHandoffPerformingV1: Sendable {
    func handoff(_ preview: FeedbackHandoffPreviewV1) async throws -> FeedbackHandoffResultV1
}

struct RecoveryCenterCoordinatorV1: Sendable {
    private let clock: any PresentationClockV1
    private let supportExport: any RecoverySupportExportPreparingV1
    private let feedbackHandoff: any RecoveryFeedbackHandoffPerformingV1

    init(clock: any PresentationClockV1,
         supportExport: any RecoverySupportExportPreparingV1,
         feedbackHandoff: any RecoveryFeedbackHandoffPerformingV1) {
        self.clock = clock
        self.supportExport = supportExport
        self.feedbackHandoff = feedbackHandoff
    }

    func project(
        sources: [RecoveryAuthoritySnapshotV1],
        operationalFailures: [OperationalFailureV1],
        encryptedBackupReceipt: TypedAvailabilityAndFallbackReceiptV1,
        supportManifest: SupportBundleManifestV1?,
        privacyPolicy: PrivacyPolicyStatusSnapshotV1
    ) throws -> RecoveryCenterProjectionV1 {
        let now = clock.monotonicNowNanoseconds()
        guard now > 0 else { throw RecoveryCenterContractFailureV1.invalidValue }
        try sources.forEach { try $0.validate() }
        try operationalFailures.forEach { try $0.validate() }
        guard Set(sources.map(\.source)).count == sources.count else {
            throw RecoveryCenterCoordinatorFailureV1.conflictingAuthorityInput
        }
        guard sources.allSatisfy({ $0.observedUptimeNanoseconds <= now }) else {
            throw RecoveryCenterCoordinatorFailureV1.conflictingAuthorityInput
        }
        let reliability = try ReliabilityStateProjectionV1(
            sources: sources,
            operationalFailures: operationalFailures,
            observedUptimeNanoseconds: now
        )
        guard reliability.state != .healthy
                || (operationalFailures.isEmpty
                    && sources.allSatisfy({ $0.state == .healthy && $0.freshness == .current })) else {
            throw RecoveryCenterCoordinatorFailureV1.conflictingAuthorityInput
        }
        let encrypted = try EncryptedBackupAvailabilityV1(receipt: encryptedBackupReceipt)
        let supportPreview = try supportManifest.map { try SupportExportPreviewProjectionV1(manifest: $0) }
        let privacy = try PrivacyDataProjectionV1(
            policy: privacyPolicy,
            backupRouteVisible: true,
            deleteRouteVisible: true,
            eraseRouteVisible: true,
            permissionRevocationRouteVisible: true
        )
        return try RecoveryCenterProjectionV1(
            reliability: reliability,
            encryptedBackup: encrypted,
            supportExportPreview: supportPreview,
            privacyData: privacy,
            observedUptimeNanoseconds: now
        )
    }

    func backupAuthoritySnapshot(
        receipt: RecoverabilityVerificationReceiptV1,
        currentArchiveSHA256: String,
        currentSourceFrontier: RecoveryPointFrontierV1,
        observedUptimeNanoseconds: UInt64
    ) throws -> RecoveryAuthoritySnapshotV1 {
        let freshness = try RecoverabilityFreshnessProjectionV1.derive(
            receipt: receipt,
            currentArchiveSHA256: currentArchiveSHA256,
            currentSourceFrontier: currentSourceFrontier
        )
        let mapped: RecoverySourceFreshnessV1
        switch freshness.disposition {
        case .currentAtVerification: mapped = .current
        case .historicAtVerification, .historicNoncurrent: mapped = .historic
        }
        let state: RecoveryCenterStateV1
        switch receipt.disposition {
        case .passed: state = mapped == .current ? .complete : .actionable
        case .failed, .quarantined: state = .validationFailed
        case .unsupported: state = .externalActionRequired
        case .cancelled: state = .interrupted
        }
        return try RecoveryAuthoritySnapshotV1(
            source: .backup,
            state: state,
            frontierRevision: currentSourceFrontier.workspaceRevision,
            frontierSHA256: currentSourceFrontier.checkpointFrontierSHA256,
            freshness: mapped,
            observedUptimeNanoseconds: observedUptimeNanoseconds
        )
    }

    func prepareSupportPreview(
        mode: SupportBundleModeV1,
        cancellation: SupportExportCancellationV1 = .never
    ) async throws -> (result: SupportExportResultV1, preview: SupportExportPreviewProjectionV1?) {
        let result = try await supportExport.prepareSupportExport(mode: mode, cancellation: cancellation)
        switch result.disposition {
        case .prepared:
            guard let manifest = result.manifest else { throw RecoveryCenterCoordinatorFailureV1.invalidSupportResult }
            return (result, try SupportExportPreviewProjectionV1(manifest: manifest))
        case .cancelled, .expired, .failed:
            guard result.manifest == nil else { throw RecoveryCenterCoordinatorFailureV1.invalidSupportResult }
            return (result, nil)
        case .shared:
            throw RecoveryCenterCoordinatorFailureV1.invalidSupportResult
        }
    }

    func previewFeedback(
        draft: SupportFeedbackDraftV1,
        destination: FeedbackHandoffDestinationV1
    ) throws -> FeedbackHandoffPreviewV1 {
        try FeedbackHandoffPreviewV1(draft: draft, destination: destination)
    }

    func handoffFeedback(
        draft: SupportFeedbackDraftV1,
        destination: FeedbackHandoffDestinationV1
    ) async throws -> FeedbackHandoffResultV1 {
        let preview = try FeedbackHandoffPreviewV1(draft: draft, destination: destination)
        let result = try await feedbackHandoff.handoff(preview)
        guard !FeedbackHandoffResultV1.claimsDeliveredOrReceived else {
            throw RecoveryCenterCoordinatorFailureV1.divergentFeedbackHandoff
        }
        switch (destination, result) {
        case (.mail, .handedToMail), (.mail, .savedInMail),
             (.mail, .cancelled), (.mail, .failed),
             (.localOnly, .localOnly), (.localOnly, .cancelled), (.localOnly, .failed):
            break
        default:
            throw RecoveryCenterCoordinatorFailureV1.divergentFeedbackHandoff
        }
        return result
    }
}

enum RecoveryCenterCoordinatorBoundaryV1 {
    static let performsCanonicalWrites = false
    static let ownsRecoveryStore = false
    static let ownsScratchStorage = false
    static let ownsRouter = false
    static let supportsFixAll = false
    static let nilSourceMeansHealthy = false
}

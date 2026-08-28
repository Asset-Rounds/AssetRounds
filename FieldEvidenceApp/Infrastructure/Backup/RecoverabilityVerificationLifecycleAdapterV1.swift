import Foundation

enum RecoverabilityVerificationInterruptionV1: Error, Equatable, Sendable {
    case afterStagingPrepared
    case afterStructureValidation
    case afterDryRestore
    case afterContentReconciliation
    case afterReplay
    case afterCleanupBeforeReceipt
    case afterReceiptCommitBeforeReturn
}

enum RecoverabilityVerificationLifecycleDispositionV1: String, Codable, Sendable {
    case purgeDerivedStaging = "PURGE_DERIVED_STAGING"
    case retainImmutableReceipt = "RETAIN_IMMUTABLE_RECEIPT"
    case includeReceiptInSubsequentBackup = "INCLUDE_RECEIPT_IN_SUBSEQUENT_BACKUP"
    case preserveHistoricNoncurrentOnCloneOrFork = "PRESERVE_HISTORIC_NONCURRENT_ON_CLONE_OR_FORK"
    case removeByGovernedRetentionOrErase = "REMOVE_BY_GOVERNED_RETENTION_OR_ERASE"
}

/// Closure composition intentionally delegates to the accepted archive,
/// isolated restore, journal replay, content, and sole-writer implementations.
/// It owns no byte store, live restore route, journal, or receipt cache.
struct RecoverabilityVerificationLifecycleOperationsV1: Sendable {
    /// Pure reservation: returns the cleanup handle before any staging bytes
    /// may be created. The returned state must be CLEANUP_REQUIRED.
    let reserveStaging: @Sendable (RecoverabilityVerificationPlanV1) async throws -> RecoverabilityVerificationStagingV1
    /// Materializes only within the reserved handle. A throw may leave bytes,
    /// so the adapter always cleans the reservation before propagating it.
    let materializeStaging: @Sendable (RecoverabilityVerificationStagingV1) async throws -> RecoverabilityVerificationStagingV1
    let validateStructure: @Sendable (RecoverabilityVerificationStagingV1) async throws -> RecoverabilityVerificationStagingV1
    let dryRestore: @Sendable (RecoverabilityVerificationStagingV1) async throws -> RecoverabilityDryRestoreArtifactsV1
    let reconcileContent: @Sendable (RecoverabilityDryRestoreArtifactsV1) async throws
        -> (staging: RecoverabilityVerificationStagingV1, receipt: RecoverabilityContentReconciliationV1)
    let replay: @Sendable (RecoverabilityDryRestoreArtifactsV1, RecoverabilityVerificationStagingV1) async throws
        -> (staging: RecoverabilityVerificationStagingV1, receipt: DeterministicRecoveryReplayReceiptV1)
    let cleanup: @Sendable (RecoverabilityVerificationStagingV1) async throws -> RecoverabilityCleanupProofV1
    let acceptedReceipt: @Sendable (RecoverabilityVerificationPlanV1) async throws
        -> RecoverabilityVerificationReceiptV1?
    let appendReceipt: @Sendable (RecoverabilityVerificationReceiptV1) async throws
        -> RecoverabilityVerificationReceiptV1

    init(
        reserveStaging: @escaping @Sendable (RecoverabilityVerificationPlanV1) async throws -> RecoverabilityVerificationStagingV1,
        materializeStaging: @escaping @Sendable (RecoverabilityVerificationStagingV1) async throws -> RecoverabilityVerificationStagingV1,
        validateStructure: @escaping @Sendable (RecoverabilityVerificationStagingV1) async throws -> RecoverabilityVerificationStagingV1,
        dryRestore: @escaping @Sendable (RecoverabilityVerificationStagingV1) async throws -> RecoverabilityDryRestoreArtifactsV1,
        reconcileContent: @escaping @Sendable (RecoverabilityDryRestoreArtifactsV1) async throws
            -> (staging: RecoverabilityVerificationStagingV1, receipt: RecoverabilityContentReconciliationV1),
        replay: @escaping @Sendable (RecoverabilityDryRestoreArtifactsV1, RecoverabilityVerificationStagingV1) async throws
            -> (staging: RecoverabilityVerificationStagingV1, receipt: DeterministicRecoveryReplayReceiptV1),
        cleanup: @escaping @Sendable (RecoverabilityVerificationStagingV1) async throws -> RecoverabilityCleanupProofV1,
        acceptedReceipt: @escaping @Sendable (RecoverabilityVerificationPlanV1) async throws
            -> RecoverabilityVerificationReceiptV1?,
        appendReceipt: @escaping @Sendable (RecoverabilityVerificationReceiptV1) async throws
            -> RecoverabilityVerificationReceiptV1
    ) {
        self.reserveStaging = reserveStaging; self.materializeStaging = materializeStaging
        self.validateStructure = validateStructure; self.dryRestore = dryRestore
        self.reconcileContent = reconcileContent; self.replay = replay; self.cleanup = cleanup
        self.acceptedReceipt = acceptedReceipt; self.appendReceipt = appendReceipt
    }
}

actor RecoverabilityVerificationLifecycleAdapterV1:
    RecoverabilityVerificationExecutingV1, RecoverabilityVerificationReceiptWritingV1 {
    typealias InterruptionHook = @Sendable (RecoverabilityVerificationInterruptionV1) throws -> Void

    private let operations: RecoverabilityVerificationLifecycleOperationsV1
    private let interruptionHook: InterruptionHook?

    init(operations: RecoverabilityVerificationLifecycleOperationsV1,
         interruptionHook: InterruptionHook? = nil) {
        self.operations = operations; self.interruptionHook = interruptionHook
    }

    func prepare(_ plan: RecoverabilityVerificationPlanV1) async throws
        -> RecoverabilityVerificationStagingV1 {
        try plan.validate()
        let reservation = try await operations.reserveStaging(plan)
        do {
            try reservation.validate()
            guard reservation.verificationID == plan.verificationID,
                  reservation.workspaceID == plan.workspaceID,
                  reservation.archive == plan.archive, reservation.mode == plan.mode,
                  reservation.state == .cleanupRequired else {
                throw RecoverabilityVerificationFailureV1.partialEffect
            }
            let staging = try await operations.materializeStaging(reservation)
            try staging.validate()
            guard staging.stagingID == reservation.stagingID,
                  staging.verificationID == reservation.verificationID,
                  staging.stagingLocatorToken == reservation.stagingLocatorToken,
                  staging.state == .prepared else {
                throw RecoverabilityVerificationFailureV1.partialEffect
            }
            try interruptionHook?(.afterStagingPrepared)
            return staging
        } catch {
            let proof: RecoverabilityCleanupProofV1
            do { proof = try await operations.cleanup(reservation) }
            catch { throw RecoverabilityVerificationFailureV1.cleanupFailed }
            try proof.validate()
            guard proof.stagingID == reservation.stagingID,
                  proof.verificationID == reservation.verificationID,
                  proof.provesIsolation else {
                throw RecoverabilityVerificationFailureV1.cleanupFailed
            }
            throw error
        }
    }

    func validateStructure(_ staging: RecoverabilityVerificationStagingV1) async throws
        -> RecoverabilityVerificationStagingV1 {
        try staging.validate()
        let result = try await operations.validateStructure(staging)
        try interruptionHook?(.afterStructureValidation)
        return result
    }

    func dryRestore(_ staging: RecoverabilityVerificationStagingV1) async throws
        -> RecoverabilityDryRestoreArtifactsV1 {
        try staging.validate()
        let result = try await operations.dryRestore(staging)
        try interruptionHook?(.afterDryRestore)
        return result
    }

    func reconcileContent(_ artifacts: RecoverabilityDryRestoreArtifactsV1) async throws
        -> (staging: RecoverabilityVerificationStagingV1, receipt: RecoverabilityContentReconciliationV1) {
        let result = try await operations.reconcileContent(artifacts)
        try interruptionHook?(.afterContentReconciliation)
        return result
    }

    func replay(_ artifacts: RecoverabilityDryRestoreArtifactsV1,
                staging: RecoverabilityVerificationStagingV1) async throws
        -> (staging: RecoverabilityVerificationStagingV1, receipt: DeterministicRecoveryReplayReceiptV1) {
        let result = try await operations.replay(artifacts, staging)
        try interruptionHook?(.afterReplay)
        return result
    }

    func cleanup(_ staging: RecoverabilityVerificationStagingV1) async throws
        -> RecoverabilityCleanupProofV1 {
        let proof = try await operations.cleanup(staging)
        try proof.validate()
        try interruptionHook?(.afterCleanupBeforeReceipt)
        return proof
    }

    func acceptedReceipt(for plan: RecoverabilityVerificationPlanV1) async throws
        -> RecoverabilityVerificationReceiptV1? {
        let receipt = try await operations.acceptedReceipt(plan)
        try receipt?.validate()
        return receipt
    }

    func append(_ receipt: RecoverabilityVerificationReceiptV1) async throws
        -> RecoverabilityVerificationReceiptV1 {
        try receipt.validate()
        let accepted = try await operations.appendReceipt(receipt)
        guard accepted == receipt else { throw RecoverabilityVerificationFailureV1.divergentRetry }
        try interruptionHook?(.afterReceiptCommitBeforeReturn)
        return accepted
    }

    nonisolated static func disposition(forStaging: Bool, isCloneOrFork: Bool,
                                        includeInArchiveBeingVerified: Bool) throws
        -> RecoverabilityVerificationLifecycleDispositionV1 {
        if forStaging { return .purgeDerivedStaging }
        guard !includeInArchiveBeingVerified else { throw RecoverabilityVerificationFailureV1.wrongArchive }
        return isCloneOrFork ? .preserveHistoricNoncurrentOnCloneOrFork : .includeReceiptInSubsequentBackup
    }
}

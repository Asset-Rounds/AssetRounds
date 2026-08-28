import Foundation

struct RecoverabilityDryRestoreArtifactsV1: Equatable, Sendable {
    let staging: RecoverabilityVerificationStagingV1
    let restoredRecordsSHA256: String

    init(staging: RecoverabilityVerificationStagingV1, restoredRecordsSHA256: String) throws {
        try staging.validate(); try RecoverabilityValidationV1.digest(restoredRecordsSHA256)
        guard staging.state == .dryRestored else { throw RecoverabilityVerificationFailureV1.partialEffect }
        self.staging = staging; self.restoredRecordsSHA256 = restoredRecordsSHA256
    }
}

protocol RecoverabilityVerificationExecutingV1: Sendable {
    func prepare(_ plan: RecoverabilityVerificationPlanV1) async throws -> RecoverabilityVerificationStagingV1
    func validateStructure(_ staging: RecoverabilityVerificationStagingV1) async throws -> RecoverabilityVerificationStagingV1
    func dryRestore(_ staging: RecoverabilityVerificationStagingV1) async throws -> RecoverabilityDryRestoreArtifactsV1
    func reconcileContent(_ artifacts: RecoverabilityDryRestoreArtifactsV1) async throws
        -> (staging: RecoverabilityVerificationStagingV1, receipt: RecoverabilityContentReconciliationV1)
    func replay(_ artifacts: RecoverabilityDryRestoreArtifactsV1,
                staging: RecoverabilityVerificationStagingV1) async throws
        -> (staging: RecoverabilityVerificationStagingV1, receipt: DeterministicRecoveryReplayReceiptV1)
    func cleanup(_ staging: RecoverabilityVerificationStagingV1) async throws -> RecoverabilityCleanupProofV1
}

protocol RecoverabilityVerificationReceiptWritingV1: Sendable {
    func acceptedReceipt(for plan: RecoverabilityVerificationPlanV1) async throws
        -> RecoverabilityVerificationReceiptV1?
    func append(_ receipt: RecoverabilityVerificationReceiptV1) async throws
        -> RecoverabilityVerificationReceiptV1
}

actor RecoverabilityVerificationCoordinatorV1 {
    private let executor: any RecoverabilityVerificationExecutingV1
    private let receiptWriter: any RecoverabilityVerificationReceiptWritingV1

    init(executor: any RecoverabilityVerificationExecutingV1,
         receiptWriter: any RecoverabilityVerificationReceiptWritingV1) {
        self.executor = executor; self.receiptWriter = receiptWriter
    }

    func verify(_ plan: RecoverabilityVerificationPlanV1, verifiedAt: Date) async throws
        -> RecoverabilityVerificationReceiptV1 {
        try plan.validate()
        if let accepted = try await receiptWriter.acceptedReceipt(for: plan) {
            try validate(accepted, matches: plan)
            return accepted
        }

        var staging: RecoverabilityVerificationStagingV1?
        do {
            var current = try await executor.prepare(plan)
            staging = current
            try validate(current, matches: plan, expectedState: .prepared)
            try Task.checkCancellation()

            current = try await executor.validateStructure(current)
            staging = current
            try validate(current, matches: plan, expectedState: .structureValidated)
            try Task.checkCancellation()

            var restoredRecordsSHA256: String?
            var dryArtifacts: RecoverabilityDryRestoreArtifactsV1?
            var reconciliation: RecoverabilityContentReconciliationV1?
            var replayReceipt: DeterministicRecoveryReplayReceiptV1?

            if plan.mode != .structureOnly {
                let artifacts = try await executor.dryRestore(current)
                try validate(artifacts.staging, matches: plan, expectedState: .dryRestored)
                guard artifacts.restoredRecordsSHA256 == plan.archive.recordsSHA256 else {
                    throw RecoverabilityVerificationFailureV1.reconciliationFailed
                }
                current = artifacts.staging; staging = current
                restoredRecordsSHA256 = artifacts.restoredRecordsSHA256; dryArtifacts = artifacts
                try Task.checkCancellation()
            }

            if plan.mode == .fullContentReconciliation, let artifacts = dryArtifacts {
                let output = try await executor.reconcileContent(artifacts)
                try validate(output.staging, matches: plan, expectedState: .contentReconciled)
                try output.receipt.validate()
                guard output.receipt.isComplete,
                      output.receipt.expectedContentManifestSHA256 == plan.archive.contentManifestSHA256 else {
                    throw RecoverabilityVerificationFailureV1.reconciliationFailed
                }
                current = output.staging; staging = current; reconciliation = output.receipt
                try Task.checkCancellation()
            }

            if plan.mode != .structureOnly, let artifacts = dryArtifacts {
                let output = try await executor.replay(artifacts, staging: current)
                try validate(output.staging, matches: plan, expectedState: .replayed)
                try output.receipt.validate()
                guard output.receipt.reconciles,
                      output.receipt.restoredCanonicalStateSHA256 == artifacts.restoredRecordsSHA256,
                      output.receipt.checkpointID == plan.archive.frontier.checkpointID else {
                    throw RecoverabilityVerificationFailureV1.replayDiverged
                }
                current = output.staging; staging = current; replayReceipt = output.receipt
                try Task.checkCancellation()
            }

            let cleanup = try await executor.cleanup(current)
            try cleanup.validate()
            guard cleanup.stagingID == current.stagingID,
                  cleanup.verificationID == plan.verificationID, cleanup.provesIsolation,
                  cleanup.sourceArchiveSHA256Before == plan.archive.archiveSHA256 else {
                throw RecoverabilityVerificationFailureV1.cleanupFailed
            }
            staging = nil

            let receipt = try RecoverabilityVerificationReceiptV1(
                receiptID: plan.receiptID, workspaceID: plan.workspaceID,
                verificationID: plan.verificationID, archive: plan.archive, mode: plan.mode,
                observedSourceFrontier: plan.observedSourceFrontier,
                freshness: plan.archive.frontier.freshness(relativeTo: plan.observedSourceFrontier),
                verifierBuild: plan.verifierBuild, restoredRecordsSHA256: restoredRecordsSHA256,
                contentReconciliation: reconciliation, replayReceipt: replayReceipt,
                cleanupProof: cleanup, disposition: .passed, findings: [], verifiedAt: verifiedAt,
                supersedesReceiptID: plan.supersedesReceiptID, revision: plan.revision,
                mutationID: plan.mutationID)
            let published = try await receiptWriter.append(receipt)
            guard published == receipt else { throw RecoverabilityVerificationFailureV1.divergentRetry }
            return published
        } catch {
            if let staging {
                let cleanup = try await executor.cleanup(staging)
                try cleanup.validate()
                guard cleanup.stagingID == staging.stagingID,
                      cleanup.verificationID == plan.verificationID, cleanup.provesIsolation else {
                    throw RecoverabilityVerificationFailureV1.cleanupFailed
                }
            }
            throw error
        }
    }

    private func validate(_ staging: RecoverabilityVerificationStagingV1,
                          matches plan: RecoverabilityVerificationPlanV1,
                          expectedState: RecoverabilityStagingStateV1) throws {
        try staging.validate()
        guard staging.verificationID == plan.verificationID,
              staging.workspaceID == plan.workspaceID, staging.archive == plan.archive,
              staging.mode == plan.mode, staging.state == expectedState else {
            throw RecoverabilityVerificationFailureV1.partialEffect
        }
    }

    private func validate(_ receipt: RecoverabilityVerificationReceiptV1,
                          matches plan: RecoverabilityVerificationPlanV1) throws {
        try receipt.validate()
        guard receipt.receiptID == plan.receiptID, receipt.verificationID == plan.verificationID,
              receipt.workspaceID == plan.workspaceID, receipt.archive == plan.archive,
              receipt.mode == plan.mode, receipt.observedSourceFrontier == plan.observedSourceFrontier,
              receipt.verifierBuild == plan.verifierBuild,
              receipt.supersedesReceiptID == plan.supersedesReceiptID,
              receipt.revision == plan.revision, receipt.mutationID == plan.mutationID else {
            throw RecoverabilityVerificationFailureV1.divergentRetry
        }
    }
}

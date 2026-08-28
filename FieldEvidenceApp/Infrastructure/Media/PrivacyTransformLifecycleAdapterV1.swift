import Foundation

enum PrivacyTransformLifecycleDispositionV1: String, Codable, Sendable {
    case retain = "RETAIN"
    case deleteRegenerableDerivative = "DELETE_REGENERABLE_DERIVATIVE"
    case quarantinePartialEffect = "QUARANTINE_PARTIAL_EFFECT"
}

enum PrivacyTransformPublicationInterruptionV1: Error, Equatable, Sendable {
    case afterVerifiedBytesBeforeCanonicalCommit
    case afterCanonicalCommitBeforeLocalReceipt
}

/// Production bridge over the existing C05 EvidenceBundleStore byte writer
/// and the sole canonical WorkspaceWriter. The two stores are intentionally
/// sequenced and recoverable; this type never describes them as one atomic
/// filesystem/database transaction.
actor WorkspacePrivacyTransformPublicationAuthorityV1: PrivacyTransformPublicationAuthorityV1 {
    typealias InterruptionHook = @Sendable (PrivacyTransformPublicationInterruptionV1) throws -> Void

    private let contentWriter: ExistingContentStorePrivacyDerivativeWriterV1
    private let workspaceWriter: WorkspaceWriterV1
    private let interruptionHook: InterruptionHook?
    private var publicationReceipts: [MutationIDV1: PrivacyTransformPublicationReceiptV1] = [:]
    private var canonicalPublicationReceipts: [MutationIDV1: MutationReceiptV1] = [:]
    private var reviewReceipts: [MutationIDV1: PrivacyReviewReceiptV1] = [:]

    init(contentWriter: any DraftImmutableContentWriterV1, workspaceWriter: WorkspaceWriterV1,
         interruptionHook: InterruptionHook? = nil) throws {
        _ = try ContentContractRegistryV1.c20BoundaryContracts()
        self.contentWriter = ExistingContentStorePrivacyDerivativeWriterV1(writer: contentWriter)
        self.workspaceWriter = workspaceWriter
        self.interruptionHook = interruptionHook
    }

    func publish(_ bundle: PrivacyTransformPublicationBundleV1) async throws -> PrivacyTransformPublicationReceiptV1 {
        try bundle.validate()
        if let existing = publicationReceipts[bundle.manifest.mutationID] {
            try await validatePublicationReceipt(existing, bundle: bundle)
            return existing
        }

        // This write is immutable and read-back verified. Repeating it after
        // interruption adopts only byte-identical content at the same ID.
        _ = try await contentWriter.persist(bytes: bundle.derivativeBytes,
                                            reference: bundle.manifest.derivative,
                                            workspaceID: bundle.manifest.workspaceID,
                                            mutationID: bundle.manifest.mutationID)
        try interruptionHook?(.afterVerifiedBytesBeforeCanonicalCommit)

        let mutation = PrivacyTransformMutationV1.publish(
            policy: bundle.policy, regions: bundle.manifest.orderedRegions,
            manifest: bundle.manifest
        )
        let canonicalReceipt = try await workspaceWriter.commitPrivacyTransform(mutation)
        _ = try PrivacyTransformMutationReceiptV1(mutation: mutation, mutationReceipt: canonicalReceipt)

        try interruptionHook?(.afterCanonicalCommitBeforeLocalReceipt)
        let receipt = try PrivacyTransformPublicationReceiptV1(
            bundle: bundle,
            canonicalMutationReceiptSHA256: canonicalReceipt.canonicalSHA256()
        )
        try receipt.validate(bundle: bundle, canonicalMutationReceipt: canonicalReceipt)
        canonicalPublicationReceipts[bundle.manifest.mutationID] = canonicalReceipt
        publicationReceipts[bundle.manifest.mutationID] = receipt
        return receipt
    }

    func receipt(for mutationID: MutationIDV1) async throws -> PrivacyTransformPublicationReceiptV1? {
        publicationReceipts[mutationID]
    }

    func validatePublicationReceipt(_ receipt: PrivacyTransformPublicationReceiptV1,
                                    bundle: PrivacyTransformPublicationBundleV1) async throws {
        guard let canonical = canonicalPublicationReceipts[bundle.manifest.mutationID] else {
            throw PrivacyTransformFailureV1.partialEffect
        }
        try receipt.validate(bundle: bundle, canonicalMutationReceipt: canonical)
    }

    func publishReview(_ review: PrivacyReviewReceiptV1, manifest: PrivacyTransformManifestV1,
                       policy: PrivacyTransformPolicyV1) async throws -> PrivacyReviewReceiptV1 {
        try review.validate(manifest: manifest, policy: policy)
        if let existing = reviewReceipts[review.mutationID] {
            guard existing == review else { throw PrivacyTransformFailureV1.digestMismatch }
            return existing
        }
        let mutation = PrivacyTransformMutationV1.review(value: review, manifest: manifest, policy: policy)
        let canonicalReceipt = try await workspaceWriter.commitPrivacyTransform(mutation)
        _ = try PrivacyTransformMutationReceiptV1(mutation: mutation, mutationReceipt: canonicalReceipt)
        try interruptionHook?(.afterCanonicalCommitBeforeLocalReceipt)
        reviewReceipts[review.mutationID] = review
        return review
    }

    func reviewReceipt(for mutationID: MutationIDV1) async throws -> PrivacyReviewReceiptV1? {
        reviewReceipts[mutationID]
    }
}

struct PrivacyTransformLifecycleAdapterV1: Sendable {
    private let coordinator: PrivacyTransformCoordinatorV1
    init(authority: any PrivacyTransformPublicationAuthorityV1) {
        coordinator = PrivacyTransformCoordinatorV1(authority: authority)
    }

    func resume(bundle: PrivacyTransformPublicationBundleV1) async throws -> PrivacyTransformPublicationReceiptV1 {
        if let receipt = try await coordinator.recover(bundle) { return receipt }
        return try await coordinator.publish(bundle)
    }

    func disposition(hasDerivativeBytes: Bool, hasManifest: Bool, hasReview: Bool, receiptValid: Bool) -> PrivacyTransformLifecycleDispositionV1 {
        if !hasDerivativeBytes && !hasManifest && !hasReview { return .retain }
        // A complete derivative publication is intentionally retained before
        // review; projections still deny it until an APPROVED receipt exists.
        if hasDerivativeBytes && hasManifest && receiptValid { return .retain }
        if hasDerivativeBytes && !hasManifest && !hasReview { return .deleteRegenerableDerivative }
        return .quarantinePartialEffect
    }
}

import Foundation

struct PrivacyTransformPublicationBundleV1: Sendable {
    let policy: PrivacyTransformPolicyV1
    let manifest: PrivacyTransformManifestV1
    let derivativeBytes: Data
    let derivativeLocator: ContentLocatorV1
    let provenance: ContentDerivativeProvenanceV1

    func validate() throws {
        try manifest.validate(policy: policy)
        guard case .privacy(let privacyProvenance) = provenance.transform else {
            throw PrivacyTransformFailureV1.invalidValue
        }
        guard manifest.workspaceID == policy.workspaceID,
              PrivacyTransformValidationV1.workspace(manifest.workspaceID, matches: derivativeLocator.workspaceID),
              derivativeLocator.contentID == manifest.derivative.contentID,
              provenance.workspaceID == manifest.derivative.workspaceID,
              provenance.derivativeContentID == manifest.derivative.contentID,
              provenance.derivativeDigest.algorithm == .sha256,
              provenance.derivativeDigest.hexadecimalValue == manifest.derivativeSHA256,
              provenance.sources.count == 1,
              provenance.sources[0].contentID == manifest.original.contentID,
              provenance.sources[0].digest.algorithm == .sha256,
              provenance.sources[0].digest.hexadecimalValue == manifest.sourceSHA256,
              privacyProvenance.privacyManifestID == manifest.manifestID,
              privacyProvenance.privacyManifestSHA256 == manifest.manifestSHA256,
              privacyProvenance.rendererID == manifest.rendererID,
              privacyProvenance.rendererVersion == manifest.rendererVersion,
              provenance.metadataSanitizerID == manifest.metadataSanitation.sanitizerID,
              provenance.metadataSanitizerVersion == manifest.metadataSanitation.sanitizerVersion else {
            throw PrivacyTransformFailureV1.invalidValue
        }
        let observed = try ContentIntegrityV1.observe(
            workspaceID: manifest.derivative.workspaceID,
            contentID: manifest.derivative.contentID,
            data: derivativeBytes,
            mediaType: manifest.derivative.mediaType
        )
        try ContentIntegrityV1.verify(reference: manifest.derivative, locator: derivativeLocator, observed: observed)
    }
}

struct PrivacyTransformPublicationReceiptV1: Codable, Equatable, Sendable {
    let mutationID: MutationIDV1
    let manifestID: UUID
    let manifestSHA256: String
    let derivativeContentID: String
    let derivativeSHA256: String
    let canonicalMutationReceiptSHA256: String

    init(bundle: PrivacyTransformPublicationBundleV1, canonicalMutationReceiptSHA256: String) throws {
        try bundle.validate()
        guard KernelCanonicalHashV1.validSHA256(canonicalMutationReceiptSHA256) else {
            throw PrivacyTransformFailureV1.digestMismatch
        }
        mutationID = bundle.manifest.mutationID
        manifestID = bundle.manifest.manifestID
        manifestSHA256 = bundle.manifest.manifestSHA256
        derivativeContentID = bundle.manifest.derivative.contentID
        derivativeSHA256 = bundle.manifest.derivativeSHA256
        self.canonicalMutationReceiptSHA256 = canonicalMutationReceiptSHA256
    }

    func validate(bundle: PrivacyTransformPublicationBundleV1,
                  expectedCanonicalMutationReceiptSHA256: String) throws {
        try bundle.validate()
        guard KernelCanonicalHashV1.validSHA256(expectedCanonicalMutationReceiptSHA256) else {
            throw PrivacyTransformFailureV1.digestMismatch
        }
        guard mutationID == bundle.manifest.mutationID,
              manifestID == bundle.manifest.manifestID,
              manifestSHA256 == bundle.manifest.manifestSHA256,
              derivativeContentID == bundle.manifest.derivative.contentID,
              derivativeSHA256 == bundle.manifest.derivativeSHA256,
              canonicalMutationReceiptSHA256 == expectedCanonicalMutationReceiptSHA256 else {
            throw PrivacyTransformFailureV1.digestMismatch
        }
    }

    func validate(bundle: PrivacyTransformPublicationBundleV1,
                  canonicalMutationReceipt: MutationReceiptV1) throws {
        let mutation = PrivacyTransformMutationV1.publish(
            policy: bundle.policy, regions: bundle.manifest.orderedRegions,
            manifest: bundle.manifest
        )
        _ = try PrivacyTransformMutationReceiptV1(
            mutation: mutation, mutationReceipt: canonicalMutationReceipt
        )
        try validate(
            bundle: bundle,
            expectedCanonicalMutationReceiptSHA256: canonicalMutationReceipt.canonicalSHA256()
        )
    }
}

/// Implemented by the existing content authority and sole WorkspaceWriter.
/// Publication is deliberately sequenced across stores: immutable derivative
/// bytes are written and read back first, then manifest/region rows commit in
/// one WorkspaceWriter transaction. Interruption may therefore leave a valid
/// unapproved derivative; retry adopts exact bytes and replays the mutation.
/// No cross-store atomicity is claimed.
protocol PrivacyTransformPublicationAuthorityV1: Sendable {
    func publish(_ bundle: PrivacyTransformPublicationBundleV1) async throws -> PrivacyTransformPublicationReceiptV1
    func receipt(for mutationID: MutationIDV1) async throws -> PrivacyTransformPublicationReceiptV1?
    func validatePublicationReceipt(_ receipt: PrivacyTransformPublicationReceiptV1,
                                    bundle: PrivacyTransformPublicationBundleV1) async throws
    func publishReview(_ review: PrivacyReviewReceiptV1, manifest: PrivacyTransformManifestV1, policy: PrivacyTransformPolicyV1) async throws -> PrivacyReviewReceiptV1
    func reviewReceipt(for mutationID: MutationIDV1) async throws -> PrivacyReviewReceiptV1?
}

struct PrivacyTransformCoordinatorV1: Sendable {
    private let authority: any PrivacyTransformPublicationAuthorityV1
    init(authority: any PrivacyTransformPublicationAuthorityV1) { self.authority = authority }

    func publish(_ bundle: PrivacyTransformPublicationBundleV1) async throws -> PrivacyTransformPublicationReceiptV1 {
        try bundle.validate()
        if let existing = try await authority.receipt(for: bundle.manifest.mutationID) {
            try await authority.validatePublicationReceipt(existing, bundle: bundle)
            return existing
        }
        let receipt = try await authority.publish(bundle)
        try await authority.validatePublicationReceipt(receipt, bundle: bundle)
        return receipt
    }

    func recover(_ bundle: PrivacyTransformPublicationBundleV1) async throws -> PrivacyTransformPublicationReceiptV1? {
        try bundle.validate()
        guard let receipt = try await authority.receipt(for: bundle.manifest.mutationID) else { return nil }
        try await authority.validatePublicationReceipt(receipt, bundle: bundle)
        return receipt
    }

    func recordReview(_ review: PrivacyReviewReceiptV1, manifest: PrivacyTransformManifestV1,
                      policy: PrivacyTransformPolicyV1) async throws -> PrivacyReviewReceiptV1 {
        try review.validate(manifest: manifest, policy: policy)
        if let existing = try await authority.reviewReceipt(for: review.mutationID) {
            guard existing == review else { throw PrivacyTransformFailureV1.digestMismatch }
            return existing
        }
        let recorded = try await authority.publishReview(review, manifest: manifest, policy: policy)
        guard recorded == review else { throw PrivacyTransformFailureV1.digestMismatch }
        return recorded
    }

    func projection(manifest: PrivacyTransformManifestV1?, review: PrivacyReviewReceiptV1?, policy: PrivacyTransformPolicyV1,
                    audience: EvidenceAudienceV1, sourceRevision: UInt64, sourceSHA256: String, now: Date) throws -> PrivacyProjectionDecisionV1 {
        try PrivacyProjectionV1.decide(manifest: manifest, review: review, policy: policy, requestedAudience: audience,
                                       currentSourceRevision: sourceRevision, currentSourceSHA256: sourceSHA256, at: now)
    }
}

extension PrivacyTransformCoordinatorV1 {
    func privateSystemDiscoveryShareDescriptor(workspaceID: WorkspaceID, audience: EvidenceAudienceV1,
                                               manifest: PrivacyTransformManifestV1, review: PrivacyReviewReceiptV1,
                                               policy: PrivacyTransformPolicyV1, now: Date) throws
        -> PrivateSystemDiscoveryShareDescriptorV1 {
        let derivative = try PrivateSystemDiscoveryPrivacyTransformBoundaryV1.validateLocalShare(
            manifest: manifest, review: review, policy: policy, audience: audience, now: now
        )
        return try PrivateSystemDiscoveryShareDescriptorV1(workspaceID: workspaceID, audience: audience,
            content: derivative, privacyManifest: manifest, policy: policy, review: review, now: now)
    }
}

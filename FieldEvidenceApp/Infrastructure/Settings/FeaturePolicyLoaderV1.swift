import Foundation

enum FeaturePolicyLoaderFailureV1: Error, Equatable, Sendable {
    case missingResource
    case duplicateResource
    case malformedResource
    case noncanonicalResource
    case digestMismatch
}

final class BundleFeaturePolicyDataProviderV1: BundledFeaturePolicyDataPortV1, @unchecked Sendable {
    static let resourceName = "FeaturePolicyV1"
    static let resourceExtension = "json"
    static let releasedResourceDigest =
        "5f6f781a3a8ead62cb7d108de688cf801a01d58802cc909e4ee118c09c029fa6"

    private let bundle: Bundle
    private let expectedDigest: String

    init(
        bundle: Bundle = .main,
        expectedDigest: String = Self.releasedResourceDigest
    ) {
        self.bundle = bundle
        self.expectedDigest = expectedDigest
    }

    func canonicalFeaturePolicyData() throws -> Data {
        let matches = (bundle.urls(
            forResourcesWithExtension: Self.resourceExtension,
            subdirectory: nil
        ) ?? []).filter { $0.deletingPathExtension().lastPathComponent == Self.resourceName }
        guard !matches.isEmpty else { throw FeaturePolicyLoaderFailureV1.missingResource }
        guard matches.count == 1, let url = matches.first else {
            throw FeaturePolicyLoaderFailureV1.duplicateResource
        }
        let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard CompatibilityCanonicalV1.validSHA256(expectedDigest),
              CompatibilityCanonicalV1.sha256(bytes) == expectedDigest else {
            throw FeaturePolicyLoaderFailureV1.digestMismatch
        }
        return bytes
    }

    func buildArtifactDigest() throws -> String {
        CompatibilityCanonicalV1.sha256(try canonicalFeaturePolicyData())
    }
}

struct FeaturePolicyLoaderV1: Sendable {
    private let provider: any BundledFeaturePolicyDataPortV1

    init(provider: any BundledFeaturePolicyDataPortV1) {
        self.provider = provider
    }

    func load() throws -> FeaturePolicyRegistryV1 {
        try loadWithDigest().registry
    }

    private func loadWithDigest() throws -> (
        registry: FeaturePolicyRegistryV1,
        digest: String
    ) {
        let raw = try provider.canonicalFeaturePolicyData()
        let reportedDigest = try provider.buildArtifactDigest()
        guard CompatibilityCanonicalV1.validSHA256(reportedDigest),
              reportedDigest == CompatibilityCanonicalV1.sha256(raw) else {
            throw FeaturePolicyLoaderFailureV1.digestMismatch
        }
        let payload: Data
        if raw.suffix(2) == Data([0x0D, 0x0A]) { payload = Data(raw.dropLast(2)) }
        else if raw.last == 0x0A { payload = Data(raw.dropLast()) }
        else { payload = raw }
        let decoded: FeaturePolicyRegistryV1
        do {
            decoded = try JSONDecoder().decode(FeaturePolicyRegistryV1.self, from: payload)
            try decoded.validate()
        } catch {
            throw FeaturePolicyLoaderFailureV1.malformedResource
        }
        let canonical = try CompatibilityCanonicalV1.encode(decoded)
        guard canonical == payload else {
            throw FeaturePolicyLoaderFailureV1.noncanonicalResource
        }
        return (decoded, reportedDigest)
    }

    func resolve(featureID: String) throws -> FeaturePolicyResolutionV1 {
        let loaded = try loadWithDigest()
        let registry = loaded.registry
        guard let feature = registry.features.first(where: { $0.featureID == featureID }) else {
            throw CapabilityContractFailureV1.unknownFeature
        }
        return FeaturePolicyResolutionV1(
            featureID: feature.featureID,
            policyState: feature.state,
            requiredPackageIDs: feature.requiredPackageIDs,
            requiredCapabilities: feature.requiredCapabilities,
            minimumPlatformMajorVersion: feature.minimumPlatformMajorVersion,
            safeFallback: feature.safeFallback,
            bundleDigest: loaded.digest
        )
    }
}

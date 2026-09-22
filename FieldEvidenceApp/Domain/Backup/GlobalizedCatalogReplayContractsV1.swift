import Foundation

enum GlobalizedCatalogReplayFailureV1: Error, Equatable, Sendable {
    case invalidSource
    case artifactMismatch
    case invalidResources
    case searchSourceMismatch
}

/// Disposable observations over the existing backup owners. These values are
/// never canonical records, archive members, or presentation preferences.
enum GlobalizedReplayLimitationV1: String, Codable, Equatable, Sendable {
    case historicalCatalogUnavailable
    case historicalCatalogReaderIncompatible
    case legacyArtifactHasNoReplayProvenance
    case historicalFontUnavailable
    case rendererEnvironmentUnavailable
    case documentCatalogReferenceNotRecorded
    case historicalSourceBindingUnavailable
    case regenerationNotVerified
}

struct GlobalizedCatalogReplayReferenceV1: Equatable, Sendable {
    let ownerID: String
    let legacyReleaseSHA256: String
    let resolvedReleaseID: V30CatalogReleaseIDV1?
    let limitation: GlobalizedReplayLimitationV1?
}

struct GlobalizedArtifactReplayObservationV1: Equatable, Sendable {
    let reportID: UUID
    let sourceSHA256: String
    let outputSHA256: String
    let outputByteCount: Int
    let metadata: GlobalizedDocumentPDFMetadataV1?
    let limitations: [GlobalizedReplayLimitationV1]

    var sourceBindingVerified: Bool {
        metadata != nil && !limitations.contains(.historicalSourceBindingUnavailable)
    }

    // Availability of dependencies alone never proves deterministic re-rendering.
    var regenerationVerified: Bool { false }
}

struct GlobalizedCatalogReplayInventoryV1: Equatable, Sendable {
    let recordsSHA256: String
    let catalogs: [GlobalizedCatalogReplayReferenceV1]
    let artifacts: [GlobalizedArtifactReplayObservationV1]
    let unrenderedReportIDs: [UUID]
}

struct GlobalizedRestoreReplayObservationV1: Equatable, Sendable {
    let inventory: GlobalizedCatalogReplayInventoryV1
    let searchSource: SearchSourceRevisionV1?
    /// The existing restore owner drops projections. Only a successful rebuild
    /// for this exact canonical revision can clear the pending state.
    let searchRebuildRequired: Bool

    var searchRevisionUnavailable: Bool { searchSource == nil }
}

/// Exact resource observations, supplied by the caller for this invocation.
/// Empty values mean unavailable/unobserved, never "use the current locale".
struct GlobalizedReplayResourcesV1: Sendable {
    let catalogs: [V30CatalogReleaseArchiveV1]
    let readerVersion: Int
    let fonts: [GlobalizedDocumentFontProvenanceV1]
    let rendererID: String?
    let rendererVersion: String?
    let operatingSystemBuild: String?

    init(catalogs: [V30CatalogReleaseArchiveV1] = [], readerVersion: Int = 1,
         fonts: [GlobalizedDocumentFontProvenanceV1] = [], rendererID: String? = nil,
         rendererVersion: String? = nil, operatingSystemBuild: String? = nil) {
        self.catalogs = catalogs; self.readerVersion = readerVersion; self.fonts = fonts
        self.rendererID = rendererID; self.rendererVersion = rendererVersion
        self.operatingSystemBuild = operatingSystemBuild
    }

    func validate() throws {
        guard readerVersion > 0, catalogs.count <= 256, fonts.count <= 256 else {
            throw GlobalizedCatalogReplayFailureV1.invalidResources
        }
        try catalogs.forEach {
            _ = try V30CatalogReleaseArchiveV1(descriptor: $0.descriptor,
                sourceCatalog: $0.sourceCatalog, registry: $0.registry, localeManifest: $0.localeManifest)
        }
        try fonts.forEach { try $0.validate() }
        if !catalogs.isEmpty { _ = try LocalizationCatalogReleaseStoreV1(archives: catalogs) }
    }
}

import Foundation

enum V30CatalogStoreFailureV1: Error, Equatable {
    case invalidArchive
    case duplicateRevision
    case missingRelease
    case missingPredecessor
    case incompatibleTransition
    case fallbackRequiresExplicitPolicy
}

/// Immutable copies of the exact bundled bytes. No runtime download or
/// workspace write is part of catalog loading.
struct V30CatalogReleaseArchiveV1: Equatable, Sendable {
    let descriptor: V30CatalogReleaseDescriptorV1
    let sourceCatalog: Data
    let registry: Data
    let localeManifest: Data

    init(
        descriptor: V30CatalogReleaseDescriptorV1,
        sourceCatalog: Data, registry: Data, localeManifest: Data
    ) throws {
        guard [sourceCatalog, registry, localeManifest].allSatisfy({
            !$0.isEmpty && $0.count <= 2_097_152
        }) else { throw V30CatalogStoreFailureV1.invalidArchive }
        try descriptor.validatePayloads(
            sourceCatalog: sourceCatalog, registry: registry, localeManifest: localeManifest
        )
        let keys = try JSONDecoder().decode(LocalizationKeyRegistryV1.self, from: registry)
        // Use the inherited validator for English/Base catalog semantics.
        // Matching hashes alone cannot make malformed content usable.
        try BundledLocalizationCatalogV1.validateSourceCatalog(sourceCatalog, registry: keys)
        self.descriptor = descriptor
        self.sourceCatalog = sourceCatalog
        self.registry = registry
        self.localeManifest = localeManifest
    }

    func keyRegistry() throws -> LocalizationKeyRegistryV1 {
        let value = try JSONDecoder().decode(LocalizationKeyRegistryV1.self, from: registry)
        try value.validate()
        return value
    }
}

enum V30CatalogFallbackReasonV1: String, Equatable, Sendable {
    case exact = "EXACT"
    case englishRequestedLanguageUnavailable = "ENGLISH_REQUESTED_LANGUAGE_UNAVAILABLE"
}

struct V30CatalogResolutionV1: Equatable, Sendable {
    let requestedLanguage: AppLanguageTagV1
    let archive: V30CatalogReleaseArchiveV1
    let fallback: V30CatalogFallbackReasonV1
    var effectiveLanguage: AppLanguageTagV1 { archive.descriptor.language }
    var finalAcceptanceClaimed: Bool { false }
}

/// Rebuild from bundled archives at launch. Every supplied predecessor remains
/// addressable by exact identity after activation or rollback. This store has
/// no filesystem writer, network client, or "latest" historical fallback.
struct LocalizationCatalogReleaseStoreV1 {
    private struct Slot: Hashable {
        let family: String
        let language: AppLanguageTagV1
    }

    private let archives: [V30CatalogReleaseIDV1: V30CatalogReleaseArchiveV1]
    private var active: [Slot: V30CatalogReleaseIDV1] = [:]

    init(archives supplied: [V30CatalogReleaseArchiveV1]) throws {
        guard !supplied.isEmpty, supplied.count <= 256 else {
            throw V30CatalogStoreFailureV1.invalidArchive
        }
        var indexed: [V30CatalogReleaseIDV1: V30CatalogReleaseArchiveV1] = [:]
        for archive in supplied {
            try archive.descriptor.validate()
            if let existing = indexed[archive.descriptor.releaseID] {
                guard existing == archive else { throw V30CatalogStoreFailureV1.invalidArchive }
            } else {
                guard !indexed.values.contains(where: {
                    $0.descriptor.family == archive.descriptor.family
                        && $0.descriptor.language == archive.descriptor.language
                        && $0.descriptor.revision == archive.descriptor.revision
                }) else { throw V30CatalogStoreFailureV1.duplicateRevision }
                indexed[archive.descriptor.releaseID] = archive
            }
        }
        var declaredSuccessors: Set<V30CatalogReleaseIDV1> = []
        for archive in indexed.values {
            if let priorID = archive.descriptor.supersedesReleaseID {
                guard declaredSuccessors.insert(priorID).inserted else {
                    throw V30CatalogStoreFailureV1.incompatibleTransition
                }
                guard let prior = indexed[priorID] else {
                    throw V30CatalogStoreFailureV1.missingPredecessor
                }
                try archive.descriptor.validateSuccessor(
                    of: prior.descriptor,
                    keyRegistry: archive.keyRegistry(),
                    previousKeyRegistry: prior.keyRegistry()
                )
            }
        }
        self.archives = indexed
    }

    func historical(
        releaseID: V30CatalogReleaseIDV1, readerVersion: Int
    ) throws -> V30CatalogReleaseArchiveV1 {
        guard let archive = archives[releaseID] else { throw V30CatalogStoreFailureV1.missingRelease }
        try archive.descriptor.validateCompatible(readerVersion: readerVersion)
        return archive
    }

    mutating func activate(releaseID: V30CatalogReleaseIDV1, readerVersion: Int) throws {
        let archive = try historical(releaseID: releaseID, readerVersion: readerVersion)
        let slot = Slot(family: archive.descriptor.family, language: archive.descriptor.language)
        if let current = active[slot], current != releaseID {
            guard descends(releaseID, from: current) else {
                throw V30CatalogStoreFailureV1.incompatibleTransition
            }
        }
        active[slot] = releaseID
    }

    mutating func rollback(to releaseID: V30CatalogReleaseIDV1, readerVersion: Int) throws {
        let archive = try historical(releaseID: releaseID, readerVersion: readerVersion)
        let slot = Slot(family: archive.descriptor.family, language: archive.descriptor.language)
        guard let current = active[slot],
              current == releaseID || descends(current, from: releaseID) else {
            throw V30CatalogStoreFailureV1.incompatibleTransition
        }
        active[slot] = releaseID
    }

    func resolve(
        family: String, requestedLanguage: AppLanguageTagV1,
        readerVersion: Int, allowsEnglishFallback: Bool
    ) throws -> V30CatalogResolutionV1 {
        if let id = active[Slot(family: family, language: requestedLanguage)] {
            return V30CatalogResolutionV1(
                requestedLanguage: requestedLanguage,
                archive: try historical(releaseID: id, readerVersion: readerVersion),
                fallback: .exact
            )
        }
        guard allowsEnglishFallback else {
            throw V30CatalogStoreFailureV1.fallbackRequiresExplicitPolicy
        }
        guard requestedLanguage != .english,
              let englishID = active[Slot(family: family, language: .english)] else {
            throw V30CatalogStoreFailureV1.missingRelease
        }
        return V30CatalogResolutionV1(
            requestedLanguage: requestedLanguage,
            archive: try historical(releaseID: englishID, readerVersion: readerVersion),
            fallback: .englishRequestedLanguageUnavailable
        )
    }

    private func descends(_ candidate: V30CatalogReleaseIDV1, from ancestor: V30CatalogReleaseIDV1) -> Bool {
        var cursor: V30CatalogReleaseIDV1? = candidate
        var visited: Set<V30CatalogReleaseIDV1> = []
        while let id = cursor, visited.insert(id).inserted {
            if id == ancestor { return true }
            cursor = archives[id]?.descriptor.supersedesReleaseID
        }
        return false
    }
}

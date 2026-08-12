import CryptoKit
import Foundation

struct EvidenceBundleInput: Sendable {
    let originalJPEG: Data
    let thumbnailJPEG: Data
}

struct StagedEvidenceBundle: Equatable, Sendable {
    let evidenceID: UUID
    let stagingDirectoryRelativePath: String
    let originalRelativePath: String
    let thumbnailRelativePath: String
    let originalByteCount: Int
    let thumbnailByteCount: Int
    let originalSHA256: String
    let thumbnailSHA256: String
}

struct PromotedEvidenceBundle: Equatable, Sendable {
    let evidenceID: UUID
    let originalRelativePath: String
    let thumbnailRelativePath: String
    let originalByteCount: Int
    let thumbnailByteCount: Int
    let originalSHA256: String
    let thumbnailSHA256: String
}

enum EvidenceBundleStoreError: Error, Equatable {
    case generationRootInvalid
    case unsafePath
    case stagingBundleAlreadyExists
    case promotedBundleAlreadyExists
    case bundleMissing
    case bundleShapeInvalid
    case fileTypeInvalid
    case canonicalJPEGInvalid
    case bundleFactsMismatch
    case promotedBundleNotOwned
    case fileOperationFailed
}

actor EvidenceBundleStore {
    private let generationRootURL: URL
    private let fileManager: FileManager

    init(
        generationRootURL: URL,
        fileManager: FileManager = .default
    ) {
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func stage(
        evidenceID: UUID,
        input: EvidenceBundleInput
    ) throws -> StagedEvidenceBundle {
        try validateCanonicalJPEG(input.originalJPEG, kind: .original)
        try validateCanonicalJPEG(input.thumbnailJPEG, kind: .thumbnail)

        let paths = paths(for: evidenceID)
        try validateGenerationRoot()
        try ensureDirectory(relativeComponents: [".staging"])
        try ensureDirectory(relativeComponents: [".staging", "evidence"])

        guard try itemType(at: paths.stagingDirectoryURL) == nil else {
            throw EvidenceBundleStoreError.stagingBundleAlreadyExists
        }
        guard try itemType(at: paths.promotedDirectoryURL) == nil else {
            throw EvidenceBundleStoreError.promotedBundleAlreadyExists
        }

        do {
            try fileManager.createDirectory(
                at: paths.stagingDirectoryURL,
                withIntermediateDirectories: false
            )
            try input.originalJPEG.write(
                to: paths.stagingOriginalURL,
                options: .atomic
            )
            try input.thumbnailJPEG.write(
                to: paths.stagingThumbnailURL,
                options: .atomic
            )

            let facts = try verifyBundle(
                directoryURL: paths.stagingDirectoryURL,
                evidenceID: evidenceID,
                paths: paths
            )
            guard facts.originalByteCount == input.originalJPEG.count,
                  facts.thumbnailByteCount == input.thumbnailJPEG.count else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
            return StagedEvidenceBundle(
                evidenceID: evidenceID,
                stagingDirectoryRelativePath: paths.stagingDirectoryRelativePath,
                originalRelativePath: paths.originalRelativePath,
                thumbnailRelativePath: paths.thumbnailRelativePath,
                originalByteCount: facts.originalByteCount,
                thumbnailByteCount: facts.thumbnailByteCount,
                originalSHA256: facts.originalSHA256,
                thumbnailSHA256: facts.thumbnailSHA256
            )
        } catch {
            try? removeExactStagingDirectoryIfPresent(paths.stagingDirectoryURL)
            if let failure = error as? EvidenceBundleStoreError {
                throw failure
            }
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    func stage(
        evidenceID: UUID,
        normalized: NormalizedMediaV1
    ) throws -> StagedEvidenceBundle {
        try stage(
            evidenceID: evidenceID,
            input: EvidenceBundleInput(
                originalJPEG: normalized.originalJPEG,
                thumbnailJPEG: normalized.thumbnailJPEG
            )
        )
    }

    func promote(_ staged: StagedEvidenceBundle) throws -> PromotedEvidenceBundle {
        let paths = paths(for: staged.evidenceID)
        try validateGenerationRoot()
        try ensureDirectory(relativeComponents: ["evidence"])
        guard try itemType(at: paths.promotedDirectoryURL) == nil else {
            throw EvidenceBundleStoreError.promotedBundleAlreadyExists
        }

        let stagedFacts = try verifyBundle(
            directoryURL: paths.stagingDirectoryURL,
            evidenceID: staged.evidenceID,
            paths: paths
        )
        guard staged.stagingDirectoryRelativePath == paths.stagingDirectoryRelativePath,
              staged.originalRelativePath == paths.originalRelativePath,
              staged.thumbnailRelativePath == paths.thumbnailRelativePath,
              staged.originalByteCount == stagedFacts.originalByteCount,
              staged.thumbnailByteCount == stagedFacts.thumbnailByteCount,
              staged.originalSHA256 == stagedFacts.originalSHA256,
              staged.thumbnailSHA256 == stagedFacts.thumbnailSHA256 else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }

        var didPromote = false
        do {
            // Both directories are in the same immutable generation, so this is
            // one atomic publication of the verified original+thumbnail pair.
            try fileManager.moveItem(
                at: paths.stagingDirectoryURL,
                to: paths.promotedDirectoryURL
            )
            didPromote = true
            let promotedFacts = try verifyBundle(
                directoryURL: paths.promotedDirectoryURL,
                evidenceID: staged.evidenceID,
                paths: paths
            )
            guard promotedFacts == stagedFacts else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
            return PromotedEvidenceBundle(
                evidenceID: staged.evidenceID,
                originalRelativePath: paths.originalRelativePath,
                thumbnailRelativePath: paths.thumbnailRelativePath,
                originalByteCount: promotedFacts.originalByteCount,
                thumbnailByteCount: promotedFacts.thumbnailByteCount,
                originalSHA256: promotedFacts.originalSHA256,
                thumbnailSHA256: promotedFacts.thumbnailSHA256
            )
        } catch {
            // The final path was absent immediately before our rename. If this
            // attempt created it but verification failed, it is still unowned.
            if didPromote {
                try? removeExactDirectoryIfPresent(paths.promotedDirectoryURL)
            }
            if let failure = error as? EvidenceBundleStoreError {
                throw failure
            }
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    func discardStaging(evidenceID: UUID) throws {
        let target = paths(for: evidenceID).stagingDirectoryURL
        try validateGenerationRoot()
        guard let type = try itemType(at: target) else {
            return
        }
        guard type == .typeDirectory else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }
        do {
            try fileManager.removeItem(at: target)
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    func removePromotedBundleIfOwned(_ promoted: PromotedEvidenceBundle) throws {
        let paths = paths(for: promoted.evidenceID)
        try validateGenerationRoot()
        guard try itemType(at: paths.promotedDirectoryURL) != nil else {
            return
        }
        let facts = try verifyBundle(
            directoryURL: paths.promotedDirectoryURL,
            evidenceID: promoted.evidenceID,
            paths: paths
        )
        guard promoted.originalRelativePath == paths.originalRelativePath,
              promoted.thumbnailRelativePath == paths.thumbnailRelativePath,
              promoted.originalByteCount == facts.originalByteCount,
              promoted.thumbnailByteCount == facts.thumbnailByteCount,
              promoted.originalSHA256 == facts.originalSHA256,
              promoted.thumbnailSHA256 == facts.thumbnailSHA256 else {
            throw EvidenceBundleStoreError.promotedBundleNotOwned
        }
        do {
            try fileManager.removeItem(at: paths.promotedDirectoryURL)
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    private struct BundlePaths {
        let stagingDirectoryRelativePath: String
        let originalRelativePath: String
        let thumbnailRelativePath: String
        let stagingDirectoryURL: URL
        let stagingOriginalURL: URL
        let stagingThumbnailURL: URL
        let promotedDirectoryURL: URL
        let promotedOriginalURL: URL
        let promotedThumbnailURL: URL
    }

    private struct BundleFacts: Equatable {
        let originalByteCount: Int
        let thumbnailByteCount: Int
        let originalSHA256: String
        let thumbnailSHA256: String
    }

    private func paths(for evidenceID: UUID) -> BundlePaths {
        let canonicalID = evidenceID.uuidString.lowercased()
        let stagingDirectoryRelativePath = ".staging/evidence/\(canonicalID)"
        let originalRelativePath = "evidence/\(canonicalID)/original.jpg"
        let thumbnailRelativePath = "evidence/\(canonicalID)/thumbnail.jpg"
        let stagingDirectoryURL = generationRootURL
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
            .appendingPathComponent(canonicalID, isDirectory: true)
        let promotedDirectoryURL = generationRootURL
            .appendingPathComponent("evidence", isDirectory: true)
            .appendingPathComponent(canonicalID, isDirectory: true)
        return BundlePaths(
            stagingDirectoryRelativePath: stagingDirectoryRelativePath,
            originalRelativePath: originalRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            stagingDirectoryURL: stagingDirectoryURL,
            stagingOriginalURL: stagingDirectoryURL.appendingPathComponent("original.jpg"),
            stagingThumbnailURL: stagingDirectoryURL.appendingPathComponent("thumbnail.jpg"),
            promotedDirectoryURL: promotedDirectoryURL,
            promotedOriginalURL: promotedDirectoryURL.appendingPathComponent("original.jpg"),
            promotedThumbnailURL: promotedDirectoryURL.appendingPathComponent("thumbnail.jpg")
        )
    }

    private func verifyBundle(
        directoryURL: URL,
        evidenceID: UUID,
        paths: BundlePaths
    ) throws -> BundleFacts {
        guard try itemType(at: directoryURL) == .typeDirectory else {
            throw EvidenceBundleStoreError.bundleMissing
        }
        let names: Set<String>
        do {
            names = Set(try fileManager.contentsOfDirectory(atPath: directoryURL.path))
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        guard names == ["original.jpg", "thumbnail.jpg"] else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }

        let isStaging = directoryURL.standardizedFileURL == paths.stagingDirectoryURL
        let originalURL = isStaging ? paths.stagingOriginalURL : paths.promotedOriginalURL
        let thumbnailURL = isStaging ? paths.stagingThumbnailURL : paths.promotedThumbnailURL
        try requireRegularNonsymlinkFile(originalURL)
        try requireRegularNonsymlinkFile(thumbnailURL)

        let original: Data
        let thumbnail: Data
        do {
            original = try Data(contentsOf: originalURL, options: .mappedIfSafe)
            thumbnail = try Data(contentsOf: thumbnailURL, options: .mappedIfSafe)
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        try validateCanonicalJPEG(original, kind: .original)
        try validateCanonicalJPEG(thumbnail, kind: .thumbnail)
        return BundleFacts(
            originalByteCount: original.count,
            thumbnailByteCount: thumbnail.count,
            originalSHA256: sha256(original),
            thumbnailSHA256: sha256(thumbnail)
        )
    }

    private func validateCanonicalJPEG(
        _ data: Data,
        kind: MediaContractV1.OutputKind
    ) throws {
        let facts: CanonicalJPEGFactsV1
        do {
            facts = try MediaNormalizerV1().validateCanonicalJPEG(data, kind: kind)
        } catch {
            throw EvidenceBundleStoreError.canonicalJPEGInvalid
        }
        guard facts.byteCount == data.count,
              facts.pixelWidth >= 1,
              facts.pixelHeight >= 1,
              facts.pixelWidth <= kind.longestEdgeMaximum,
              facts.pixelHeight <= kind.longestEdgeMaximum else {
            throw EvidenceBundleStoreError.canonicalJPEGInvalid
        }
    }

    private func validateGenerationRoot() throws {
        guard try itemType(at: generationRootURL) == .typeDirectory else {
            throw EvidenceBundleStoreError.generationRootInvalid
        }
        let rootPath = generationRootURL.path
        guard !rootPath.isEmpty,
              generationRootURL.standardizedFileURL.path == rootPath else {
            throw EvidenceBundleStoreError.unsafePath
        }
    }

    private func ensureDirectory(relativeComponents: [String]) throws {
        var current = generationRootURL
        for component in relativeComponents {
            guard !component.isEmpty, component != ".", component != "..",
                  !component.contains("/"), !component.contains("\\") else {
                throw EvidenceBundleStoreError.unsafePath
            }
            current.appendPathComponent(component, isDirectory: true)
            switch try itemType(at: current) {
            case nil:
                do {
                    try fileManager.createDirectory(
                        at: current,
                        withIntermediateDirectories: false
                    )
                } catch {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
            case .some(.typeDirectory):
                break
            case .some:
                throw EvidenceBundleStoreError.bundleShapeInvalid
            }
        }
    }

    private func requireRegularNonsymlinkFile(_ url: URL) throws {
        guard try itemType(at: url) == .typeRegular else {
            throw EvidenceBundleStoreError.fileTypeInvalid
        }
    }

    private func itemType(at url: URL) throws -> FileAttributeType? {
        guard isInsideGeneration(url) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.type] as? FileAttributeType
        } catch let error as CocoaError where
            error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    private func isInsideGeneration(_ url: URL) -> Bool {
        let root = generationRootURL.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private func removeExactStagingDirectoryIfPresent(_ url: URL) throws {
        guard let type = try itemType(at: url) else { return }
        guard type == .typeDirectory else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }
        try fileManager.removeItem(at: url)
    }

    private func removeExactDirectoryIfPresent(_ url: URL) throws {
        guard let type = try itemType(at: url) else { return }
        guard type == .typeDirectory else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }
        try fileManager.removeItem(at: url)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

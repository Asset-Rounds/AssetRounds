import Darwin
import Foundation

enum BackupImportServiceError: Error, Equatable {
    case invalidGeneration
    case securityScopeDenied
    case coordinationFailed
    case invalidSource
    case copyFailed
    case cleanupFailed
}

struct BackupSecurityScopedAccessV1 {
    let start: (URL) -> Bool
    let stop: (URL) -> Void

    static let live = BackupSecurityScopedAccessV1(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )

    static let alreadyAuthorized = BackupSecurityScopedAccessV1(
        start: { _ in true },
        stop: { _ in }
    )
}

final class BackupImportService {
    private struct SourceBoundary {
        let manifest: V4BackupManifestV1
        let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    }

    private let generationRootURL: URL
    private let generationRootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let stagingDirectoryURL: URL
    private let storagePreflight: StoragePreflightService
    private let validator: BackupPackageValidatorV1
    private let fileManager: FileManager
    private let makeUUID: () -> UUID
    private let scopedAccess: BackupSecurityScopedAccessV1

    init(
        generationRootURL: URL,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        validator: BackupPackageValidatorV1 = BackupPackageValidatorV1(),
        fileManager: FileManager = .default,
        makeUUID: @escaping () -> UUID = UUID.init,
        scopedAccess: BackupSecurityScopedAccessV1 = .live
    ) throws {
        let root = generationRootURL.standardizedFileURL
        do {
            generationRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
            stagingDirectoryURL = try StoreGenerationFactory
                .backupImportStagingDirectory(containing: root)
        } catch {
            throw BackupImportServiceError.invalidGeneration
        }
        self.generationRootURL = root
        self.storagePreflight = storagePreflight
        self.validator = validator
        self.fileManager = fileManager
        self.makeUUID = makeUUID
        self.scopedAccess = scopedAccess
    }

    func stageAndValidate(
        selectedPackageURL: URL
    ) throws -> ValidatedV4BackupPackageV1 {
        guard selectedPackageURL.isFileURL else {
            throw BackupImportServiceError.invalidSource
        }
        let selected = selectedPackageURL.standardizedFileURL
        guard selected.pathExtension == "fieldrecordbackup",
              selected.lastPathComponent
                == selected.lastPathComponent.precomposedStringWithCanonicalMapping,
              scopedAccess.start(selected) else {
            throw BackupImportServiceError.securityScopeDenied
        }
        defer { scopedAccess.stop(selected) }

        var coordinationError: NSError?
        var coordinatedResult: Result<ValidatedV4BackupPackageV1, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: selected,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            coordinatedResult = Result {
                try stageAndValidateCoordinatedSource(
                    coordinatedURL.standardizedFileURL
                )
            }
        }
        if coordinationError != nil {
            throw BackupImportServiceError.coordinationFailed
        }
        guard let coordinatedResult else {
            throw BackupImportServiceError.coordinationFailed
        }
        return try coordinatedResult.get()
    }

    func discard(_ value: ValidatedV4BackupPackageV1) throws {
        try requireCurrentGeneration()
        try cleanupOwnedPackage(at: value.stagedPackageURL)
    }
}

private extension BackupImportService {
    func stageAndValidateCoordinatedSource(
        _ sourceURL: URL
    ) throws -> ValidatedV4BackupPackageV1 {
        try requireCurrentGeneration()
        let source = try validateSourceBoundary(sourceURL)
        let applicationSupportURL = stagingDirectoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try storagePreflight.checkBackupImport(
            declaredPayloadByteCount: Int64(source.manifest.declaredPayloadByteCount),
            onVolumeContaining: applicationSupportURL
        )
        try requireCurrentGeneration()
        try prepareStagingDirectory()

        let operationID = makeUUID()
        let destinationURL = stagingDirectoryURL.appendingPathComponent(
            "\(operationID.uuidString.lowercased()).fieldrecordbackup",
            isDirectory: true
        )
        guard try itemInformation(at: destinationURL) == nil else {
            throw BackupImportServiceError.invalidSource
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            if try itemInformation(at: destinationURL) != nil {
                do { try cleanupOwnedPackage(at: destinationURL) }
                catch { throw BackupImportServiceError.cleanupFailed }
            }
            throw BackupImportServiceError.copyFailed
        }

        do {
            let value = try validator.validate(stagedPackageURL: destinationURL)
            guard value.manifest == source.manifest,
                  try ReportPDFAnchoredFile.rootIdentity(at: sourceURL)
                    == source.rootIdentity else {
                throw BackupImportServiceError.invalidSource
            }
            try requireCurrentGeneration()
            return value
        } catch {
            do { try cleanupOwnedPackage(at: destinationURL) }
            catch { throw BackupImportServiceError.cleanupFailed }
            throw error
        }
    }

    private func validateSourceBoundary(_ sourceURL: URL) throws -> SourceBoundary {
        let root = sourceURL.standardizedFileURL
        guard root.pathExtension == "fieldrecordbackup",
              try itemInformation(at: root).map(isDirectory) == true else {
            throw BackupImportServiceError.invalidSource
        }
        let rootIdentity: ReportPDFAnchoredFile.RootIdentity
        let manifestData: Data
        do {
            rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
            manifestData = try ReportPDFAnchoredFile.readRegularFile(
                at: root.appendingPathComponent("manifest.json", isDirectory: false),
                within: root,
                rootIdentity: rootIdentity
            )
        } catch {
            throw BackupImportServiceError.invalidSource
        }
        let manifest: V4BackupManifestV1
        do { manifest = try BackupCanonicalDecoderV1().decodeManifest(manifestData) }
        catch { throw BackupImportServiceError.invalidSource }

        let expectedFiles = Set(["manifest.json"] + manifest.entries.map(\.path))
        let expectedDirectories = Set(manifest.entries.compactMap { entry in
            entry.path == "records.json"
                ? nil
                : entry.path.split(separator: "/").first.map(String.init)
        })
        guard try sourceShape(
            root: root,
            manifest: manifest
        ) == (expectedFiles, expectedDirectories),
              try ReportPDFAnchoredFile.rootIdentity(at: root) == rootIdentity else {
            throw BackupImportServiceError.invalidSource
        }
        return SourceBoundary(manifest: manifest, rootIdentity: rootIdentity)
    }

    func sourceShape(
        root: URL,
        manifest: V4BackupManifestV1
    ) throws -> (Set<String>, Set<String>) {
        let sizes = Dictionary(uniqueKeysWithValues: manifest.entries.map {
            ($0.path, Int64($0.byteCount))
        })
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw BackupImportServiceError.invalidSource
        }
        var files = Set<String>()
        var directories = Set<String>()
        var identities = Set<FileIdentity>()
        for case let url as URL in enumerator {
            let path = try relativePath(of: url, within: root)
            guard let information = try itemInformation(at: url) else {
                throw BackupImportServiceError.invalidSource
            }
            switch information.st_mode & S_IFMT {
            case S_IFDIR:
                guard path.split(separator: "/", omittingEmptySubsequences: false).count == 1,
                      directories.insert(path).inserted else {
                    throw BackupImportServiceError.invalidSource
                }
            case S_IFREG:
                guard information.st_nlink == 1,
                      files.insert(path).inserted,
                      identities.insert(FileIdentity(information)).inserted else {
                    throw BackupImportServiceError.invalidSource
                }
                if path != "manifest.json" {
                    guard sizes[path] == information.st_size else {
                        throw BackupImportServiceError.invalidSource
                    }
                }
            default:
                enumerator.skipDescendants()
                throw BackupImportServiceError.invalidSource
            }
        }
        return (files, directories)
    }

    func prepareStagingDirectory() throws {
        let restoreURL = stagingDirectoryURL.deletingLastPathComponent()
        let applicationSupportURL = restoreURL.deletingLastPathComponent()
        guard try itemInformation(at: applicationSupportURL).map(isDirectory) == true else {
            throw BackupImportServiceError.invalidGeneration
        }
        for directory in [restoreURL, stagingDirectoryURL] {
            if let existing = try itemInformation(at: directory) {
                guard isDirectory(existing) else {
                    throw BackupImportServiceError.invalidGeneration
                }
            } else {
                do {
                    try fileManager.createDirectory(
                        at: directory,
                        withIntermediateDirectories: false
                    )
                } catch {
                    throw BackupImportServiceError.copyFailed
                }
                guard try itemInformation(at: directory).map(isDirectory) == true else {
                    throw BackupImportServiceError.invalidGeneration
                }
            }
        }
    }

    func cleanupOwnedPackage(at packageURL: URL) throws {
        let value = packageURL.standardizedFileURL
        let parent = value.deletingLastPathComponent()
        guard parent == stagingDirectoryURL,
              value.pathExtension == "fieldrecordbackup",
              let id = UUID(uuidString: value.deletingPathExtension().lastPathComponent),
              id.uuidString.lowercased()
                == value.deletingPathExtension().lastPathComponent else {
            throw BackupImportServiceError.cleanupFailed
        }
        guard let information = try itemInformation(at: value) else { return }
        guard isDirectory(information),
              try itemInformation(at: parent).map(isDirectory) == true else {
            throw BackupImportServiceError.cleanupFailed
        }
        do { try fileManager.removeItem(at: value) }
        catch { throw BackupImportServiceError.cleanupFailed }
        guard try itemInformation(at: value) == nil else {
            throw BackupImportServiceError.cleanupFailed
        }
    }

    func requireCurrentGeneration() throws {
        do {
            guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                    == generationRootIdentity else {
                throw BackupImportServiceError.invalidGeneration
            }
        } catch let error as BackupImportServiceError {
            throw error
        } catch {
            throw BackupImportServiceError.invalidGeneration
        }
    }

    func relativePath(of url: URL, within root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let valuePath = url.standardizedFileURL.path
        guard valuePath.hasPrefix(rootPath + "/") else {
            throw BackupImportServiceError.invalidSource
        }
        let value = String(valuePath.dropFirst(rootPath.count + 1))
        guard !value.isEmpty,
              value == value.precomposedStringWithCanonicalMapping,
              !value.contains("\\"),
              !value.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw BackupImportServiceError.invalidSource
        }
        return value
    }

    func itemInformation(at url: URL) throws -> stat? {
        var information = stat()
        if Darwin.lstat(url.path, &information) == 0 { return information }
        if errno == ENOENT { return nil }
        throw BackupImportServiceError.invalidSource
    }

    func isDirectory(_ information: stat) -> Bool {
        (information.st_mode & S_IFMT) == S_IFDIR
    }
}

private struct FileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64

    init(_ value: stat) {
        device = UInt64(value.st_dev)
        inode = UInt64(value.st_ino)
    }
}

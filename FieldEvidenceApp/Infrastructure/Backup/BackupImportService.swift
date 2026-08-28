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

struct BackupSecurityScopedAccessV1: Sendable {
    let start: @Sendable (URL) -> Bool
    let stop: @Sendable (URL) -> Void

    static let live = BackupSecurityScopedAccessV1(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )

    static let alreadyAuthorized = BackupSecurityScopedAccessV1(
        start: { _ in true },
        stop: { _ in }
    )
}

/// The class is immutable after initialization. Its unchecked conformance is
/// limited to legacy injected Foundation/file-system collaborators; one job
/// owns an instance, and all mutation is descriptor-pinned on that worker.
final class BackupImportService: @unchecked Sendable {
    private struct SourceBoundary {
        let manifest: V4BackupManifestV1
        let rootIdentity: BackupPackageRootIdentity
    }

    private let generationRootURL: URL
    private let generationRootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let stagingDirectoryURL: URL
    private let storagePreflight: StoragePreflightService
    private let validator: BackupPackageValidatorV1
    private let archiveLimits: StreamingArchiveLimitsV1
    private let archiveService: StreamingArchiveService
    private let fileManager: FileManager
    private let makeUUID: @Sendable () -> UUID
    private let scopedAccess: BackupSecurityScopedAccessV1

    init(
        generationRootURL: URL,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        validator: BackupPackageValidatorV1 = BackupPackageValidatorV1(),
        archiveLimits: StreamingArchiveLimitsV1 = .card17,
        fileManager: FileManager = .default,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
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
        self.archiveLimits = archiveLimits
        self.archiveService = StreamingArchiveService(
            limits: archiveLimits,
            makeOperationID: makeUUID
        )
        self.fileManager = fileManager
        self.makeUUID = makeUUID
        self.scopedAccess = scopedAccess
    }

    func stageAndValidate(
        selectedPackageURL: URL,
        cancellation: StreamingArchiveCancellationV1 = .none
    ) throws -> ValidatedV4BackupPackageV1 {
        guard selectedPackageURL.isFileURL else {
            throw BackupImportServiceError.invalidSource
        }
        let selected = selectedPackageURL.standardizedFileURL
        guard selected.pathExtension == "fieldrecordbackup",
              selected.lastPathComponent
                == selected.lastPathComponent.precomposedStringWithCanonicalMapping,
              let selectedInformation = try itemInformation(at: selected),
              isDirectory(selectedInformation)
                || isRegularFile(selectedInformation) else {
            throw BackupImportServiceError.invalidSource
        }
        guard scopedAccess.start(selected) else {
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
                    coordinatedURL.standardizedFileURL,
                    cancellation: cancellation
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

    func stageAndValidateOffMain(
        selectedPackageURL: URL,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> ValidatedV4BackupPackageV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let taskContext = context
        return try await BackupOffMainWorkV1.run {
            try self.stageAndValidate(
                selectedPackageURL: selectedPackageURL,
                cancellation: StreamingArchiveCancellationV1 {
                    guard !Task.isCancelled else {
                        throw StreamingArchiveFailureV1.cancelled
                    }
                    try taskContext?.validateGenerationLease()
                }
            )
        }
    }

    func discard(_ value: ValidatedV4BackupPackageV1) throws {
        try requireCurrentGeneration()
        try cleanupOwnedPackage(at: value.stagedPackageURL)
    }

    func discardOffMain(
        _ value: ValidatedV4BackupPackageV1,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        try await BackupOffMainWorkV1.run {
            try self.discard(value)
        }
        try await context?.cancellationBoundary()
    }
}

private extension BackupImportService {
    private final class PinnedImportAuthority {
        let applicationSupportDescriptor: Int32
        let restoreDescriptor: Int32
        let stagingDescriptor: Int32
        let applicationSupportIdentity: FileIdentity
        let restoreIdentity: FileIdentity
        let stagingIdentity: FileIdentity
        private let applicationSupportURL: URL
        private let restoreName: String
        private let stagingName: String

        private init(
            applicationSupportDescriptor: Int32,
            restoreDescriptor: Int32,
            stagingDescriptor: Int32,
            applicationSupportIdentity: FileIdentity,
            restoreIdentity: FileIdentity,
            stagingIdentity: FileIdentity,
            applicationSupportURL: URL,
            restoreName: String,
            stagingName: String
        ) {
            self.applicationSupportDescriptor = applicationSupportDescriptor
            self.restoreDescriptor = restoreDescriptor
            self.stagingDescriptor = stagingDescriptor
            self.applicationSupportIdentity = applicationSupportIdentity
            self.restoreIdentity = restoreIdentity
            self.stagingIdentity = stagingIdentity
            self.applicationSupportURL = applicationSupportURL
            self.restoreName = restoreName
            self.stagingName = stagingName
        }

        deinit {
            _ = Darwin.close(stagingDescriptor)
            _ = Darwin.close(restoreDescriptor)
            _ = Darwin.close(applicationSupportDescriptor)
        }

        static func open(
            stagingURL: URL,
            createMissing: Bool = false
        ) throws -> PinnedImportAuthority {
            let stagingURL = stagingURL.standardizedFileURL
            let restoreURL = stagingURL.deletingLastPathComponent()
            let applicationSupportURL = restoreURL.deletingLastPathComponent()
            let applicationSupportName = applicationSupportURL.lastPathComponent
            let restoreName = restoreURL.lastPathComponent
            let stagingName = stagingURL.lastPathComponent
            guard applicationSupportURL.isFileURL,
                  restoreName == "FieldEvidenceRestore",
                  stagingName == "staging",
                  !applicationSupportName.isEmpty,
                  !applicationSupportName.contains("/") else {
                throw BackupImportServiceError.invalidGeneration
            }

            let applicationSupportDescriptor = Darwin.open(
                applicationSupportURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard applicationSupportDescriptor >= 0 else {
                throw BackupImportServiceError.invalidGeneration
            }
            var retained = [applicationSupportDescriptor]
            var succeeded = false
            defer {
                if !succeeded {
                    for descriptor in retained.reversed() {
                        _ = Darwin.close(descriptor)
                    }
                }
            }

            var restoreDescriptor = Darwin.openat(
                applicationSupportDescriptor,
                restoreName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if restoreDescriptor < 0, errno == ENOENT, createMissing {
                guard Darwin.mkdirat(
                    applicationSupportDescriptor,
                    restoreName,
                    mode_t(0o700)
                ) == 0 || errno == EEXIST,
                      Darwin.fsync(applicationSupportDescriptor) == 0 else {
                    throw BackupImportServiceError.invalidGeneration
                }
                restoreDescriptor = Darwin.openat(
                    applicationSupportDescriptor,
                    restoreName,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
            }
            guard restoreDescriptor >= 0 else {
                throw BackupImportServiceError.invalidGeneration
            }
            retained.append(restoreDescriptor)
            var stagingDescriptor = Darwin.openat(
                restoreDescriptor,
                stagingName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if stagingDescriptor < 0, errno == ENOENT, createMissing {
                guard Darwin.mkdirat(
                    restoreDescriptor,
                    stagingName,
                    mode_t(0o700)
                ) == 0 || errno == EEXIST,
                      Darwin.fsync(restoreDescriptor) == 0 else {
                    throw BackupImportServiceError.invalidGeneration
                }
                stagingDescriptor = Darwin.openat(
                    restoreDescriptor,
                    stagingName,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
            }
            guard stagingDescriptor >= 0 else {
                throw BackupImportServiceError.invalidGeneration
            }
            retained.append(stagingDescriptor)

            let applicationSupportIdentity = try identity(
                applicationSupportDescriptor
            )
            let restoreIdentity = try identity(restoreDescriptor)
            let stagingIdentity = try identity(stagingDescriptor)
            guard try entryIdentity(
                parent: applicationSupportDescriptor,
                name: restoreName
            ) == restoreIdentity,
                  try entryIdentity(
                      parent: restoreDescriptor,
                      name: stagingName
                  ) == stagingIdentity else {
                throw BackupImportServiceError.invalidGeneration
            }

            let authority = PinnedImportAuthority(
                applicationSupportDescriptor: applicationSupportDescriptor,
                restoreDescriptor: restoreDescriptor,
                stagingDescriptor: stagingDescriptor,
                applicationSupportIdentity: applicationSupportIdentity,
                restoreIdentity: restoreIdentity,
                stagingIdentity: stagingIdentity,
                applicationSupportURL: applicationSupportURL.standardizedFileURL,
                restoreName: restoreName,
                stagingName: stagingName
            )
            succeeded = true
            return authority
        }

        func verify() throws {
            guard try Self.identity(applicationSupportDescriptor)
                    == applicationSupportIdentity,
                  try Self.identity(restoreDescriptor) == restoreIdentity,
                  try Self.identity(stagingDescriptor) == stagingIdentity,
                  try Self.entryIdentity(
                      parent: applicationSupportDescriptor,
                      name: restoreName
                  ) == restoreIdentity,
                  try Self.entryIdentity(
                      parent: restoreDescriptor,
                      name: stagingName
                  ) == stagingIdentity else {
                throw BackupImportServiceError.cleanupFailed
            }
            let reopenedApplicationSupport = Darwin.open(
                applicationSupportURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard reopenedApplicationSupport >= 0 else {
                throw BackupImportServiceError.cleanupFailed
            }
            defer { _ = Darwin.close(reopenedApplicationSupport) }
            guard try Self.identity(reopenedApplicationSupport)
                    == applicationSupportIdentity else {
                throw BackupImportServiceError.cleanupFailed
            }
        }

        private static func identity(_ descriptor: Int32) throws -> FileIdentity {
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  (information.st_mode & S_IFMT) == S_IFDIR else {
                throw BackupImportServiceError.cleanupFailed
            }
            return FileIdentity(information)
        }

        private static func entryIdentity(
            parent: Int32,
            name: String
        ) throws -> FileIdentity {
            var information = stat()
            guard Darwin.fstatat(
                parent,
                name,
                &information,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
                  (information.st_mode & S_IFMT) == S_IFDIR else {
                throw BackupImportServiceError.cleanupFailed
            }
            return FileIdentity(information)
        }
    }

    func stageAndValidateCoordinatedSource(
        _ sourceURL: URL,
        cancellation: StreamingArchiveCancellationV1
    ) throws -> ValidatedV4BackupPackageV1 {
        guard let information = try itemInformation(at: sourceURL) else {
            throw BackupImportServiceError.invalidSource
        }
        if isDirectory(information) {
            return try stageAndValidateLegacyDirectory(
                sourceURL,
                cancellation: cancellation
            )
        }
        guard isRegularFile(information) else {
            throw BackupImportServiceError.invalidSource
        }
        do {
            guard try StreamingArchiveService.hasFormatMagic(at: sourceURL) else {
                throw BackupImportServiceError.invalidSource
            }
        } catch let error as BackupImportServiceError {
            throw error
        } catch {
            throw BackupImportServiceError.invalidSource
        }
        return try stageAndValidateStreamingArchive(
            sourceURL,
            cancellation: cancellation
        )
    }

    func stageAndValidateLegacyDirectory(
        _ sourceURL: URL,
        cancellation: StreamingArchiveCancellationV1
    ) throws -> ValidatedV4BackupPackageV1 {
        try cancellation.checkpoint()
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
        let importAuthority = try PinnedImportAuthority.open(
            stagingURL: stagingDirectoryURL
        )
        let verifyImportAuthority = {
            try self.requireCurrentGeneration()
            try importAuthority.verify()
        }
        try verifyImportAuthority()

        let operationID = makeUUID()
        let destinationURL = stagingDirectoryURL.appendingPathComponent(
            "\(operationID.uuidString.lowercased()).fieldrecordbackup",
            isDirectory: true
        )
        let temporaryURL = stagingDirectoryURL.appendingPathComponent(
            "\(operationID.uuidString.lowercased())-tmp.fieldrecordbackup",
            isDirectory: true
        )
        try verifyImportAuthority()
        guard try itemInformation(at: destinationURL) == nil,
              try itemInformation(at: temporaryURL) == nil else {
            throw BackupImportServiceError.invalidSource
        }

        do {
            try verifyImportAuthority()
            try cancellation.checkpoint()
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            try cancellation.checkpoint()
            try verifyImportAuthority()
            try protectStagedPackage(
                at: temporaryURL,
                authorityCheck: verifyImportAuthority
            )
        } catch {
            let originalError = error
            do {
                try verifyImportAuthority()
                if try itemInformation(at: temporaryURL) != nil {
                    try cleanupOwnedPackage(
                        at: temporaryURL,
                        verifyProtection: false,
                        authorityCheck: verifyImportAuthority
                    )
                }
            } catch {
                if isProtectedDataUnavailable(originalError) {
                    throw originalError
                }
                if isProtectedDataUnavailable(error) {
                    throw error
                }
                throw BackupImportServiceError.cleanupFailed
            }
            if isProtectedDataUnavailable(originalError) {
                throw originalError
            }
            if originalError is CancellationError
                || originalError is GenerationLeaseRegistryFailureV1
                || (originalError as? StreamingArchiveFailureV1) == .cancelled {
                throw originalError
            }
            throw BackupImportServiceError.copyFailed
        }

        do {
            let temporaryValue = try validator.validate(
                stagedPackageURL: temporaryURL,
                cancellation: cancellation
            )
            guard temporaryValue.manifest == source.manifest,
                  try BackupPackageAnchoredFile.rootIdentity(at: sourceURL)
                    == source.rootIdentity else {
                throw BackupImportServiceError.invalidSource
            }
            guard let temporaryInformation = try itemInformation(at: temporaryURL),
                  isDirectory(temporaryInformation) else {
                throw BackupImportServiceError.invalidSource
            }
            let temporaryIdentity = FileIdentity(temporaryInformation)
            try verifyImportAuthority()
            guard try itemInformation(at: temporaryURL)
                    .map(FileIdentity.init) == temporaryIdentity else {
                throw BackupImportServiceError.invalidSource
            }
            try cancellation.checkpoint()
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            try verifyImportAuthority()
            guard try itemInformation(at: destinationURL)
                    .map(FileIdentity.init) == temporaryIdentity else {
                throw BackupImportServiceError.copyFailed
            }
            try protectStagedPackage(
                at: destinationURL,
                authorityCheck: verifyImportAuthority
            )
            try verifyImportAuthority()
            guard try itemInformation(at: destinationURL)
                    .map(FileIdentity.init) == temporaryIdentity else {
                throw BackupImportServiceError.copyFailed
            }
            try cancellation.checkpoint()
            let value = try validator.validate(
                stagedPackageURL: destinationURL,
                cancellation: cancellation
            )
            guard value.manifest == source.manifest else {
                throw BackupImportServiceError.invalidSource
            }
            try verifyImportAuthority()
            guard try itemInformation(at: destinationURL)
                    .map(FileIdentity.init) == temporaryIdentity else {
                throw BackupImportServiceError.copyFailed
            }
            return value
        } catch {
            let originalError = error
            do {
                try verifyImportAuthority()
                if try itemInformation(at: temporaryURL) != nil {
                    try cleanupOwnedPackage(
                        at: temporaryURL,
                        verifyProtection: false,
                        authorityCheck: verifyImportAuthority
                    )
                }
                try verifyImportAuthority()
                if try itemInformation(at: destinationURL) != nil {
                    try cleanupOwnedPackage(
                        at: destinationURL,
                        verifyProtection: false,
                        authorityCheck: verifyImportAuthority
                    )
                }
            } catch {
                let cleanupError = error
                if isProtectedDataUnavailable(originalError) {
                    throw originalError
                }
                if isProtectedDataUnavailable(cleanupError) {
                    throw cleanupError
                }
                throw BackupImportServiceError.cleanupFailed
            }
            if isProtectedDataUnavailable(originalError) {
                throw originalError
            }
            throw originalError
        }
    }

    func stageAndValidateStreamingArchive(
        _ sourceURL: URL,
        cancellation: StreamingArchiveCancellationV1
    ) throws -> ValidatedV4BackupPackageV1 {
        try requireCurrentGeneration()
        let applicationSupportURL = stagingDirectoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try prepareStagingDirectory()
        let importAuthority = try PinnedImportAuthority.open(
            stagingURL: stagingDirectoryURL
        )
        let verifyImportAuthority = {
            try self.requireCurrentGeneration()
            try importAuthority.verify()
        }
        try verifyImportAuthority()

        let operationID = makeUUID()
        let destinationURL = stagingDirectoryURL.appendingPathComponent(
            "\(operationID.uuidString.lowercased()).fieldrecordbackup",
            isDirectory: true
        )
        let temporaryURL = stagingDirectoryURL.appendingPathComponent(
            "\(operationID.uuidString.lowercased())-tmp.fieldrecordbackup",
            isDirectory: true
        )
        guard try itemInformation(at: destinationURL) == nil,
              try itemInformation(at: temporaryURL) == nil else {
            throw BackupImportServiceError.invalidSource
        }

        do {
            try cancellation.checkpoint()
            try verifyImportAuthority()
            let extraction = try archiveService.extract(
                sourceURL,
                to: temporaryURL,
                cancellation: cancellation,
                storageCheck: { requiredBytes in
                    let payloadBytes = requiredBytes
                        - self.archiveLimits.stagingReserveByteCount
                    guard payloadBytes >= 0 else {
                        throw StreamingArchiveFailureV1.uncompressedLimitExceeded
                    }
                    try self.storagePreflight.checkBackupImport(
                        declaredPayloadByteCount: payloadBytes,
                        onVolumeContaining: applicationSupportURL
                    )
                }
            )
            guard extraction.extractedDirectoryURL.standardizedFileURL
                    == temporaryURL else {
                throw BackupImportServiceError.invalidSource
            }
            try verifyImportAuthority()
            try protectStagedPackage(
                at: temporaryURL,
                authorityCheck: verifyImportAuthority
            )
            let temporaryValue = try validator.validate(
                stagedPackageURL: temporaryURL,
                cancellation: cancellation
            )
            let indexByPath = Dictionary(
                uniqueKeysWithValues: extraction.index.entries.map { ($0.path, $0) }
            )
            guard temporaryValue.members.keys == Set(indexByPath.keys),
                  temporaryValue.members.keys.allSatisfy({ path in
                      guard let descriptor = temporaryValue.members.descriptors[path],
                            let archived = indexByPath[path] else { return false }
                      return descriptor.byteCount == archived.uncompressedByteCount
                        && descriptor.sha256 == archived.contentSHA256
                  }) else {
                throw BackupImportServiceError.invalidSource
            }

            guard let temporaryInformation = try itemInformation(at: temporaryURL),
                  isDirectory(temporaryInformation) else {
                throw BackupImportServiceError.invalidSource
            }
            let temporaryIdentity = FileIdentity(temporaryInformation)
            try cancellation.checkpoint()
            try verifyImportAuthority()
            guard try itemInformation(at: temporaryURL)
                    .map(FileIdentity.init) == temporaryIdentity else {
                throw BackupImportServiceError.invalidSource
            }
            try cancellation.checkpoint()
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            try verifyImportAuthority()
            guard try itemInformation(at: destinationURL)
                    .map(FileIdentity.init) == temporaryIdentity else {
                throw BackupImportServiceError.copyFailed
            }
            try protectStagedPackage(
                at: destinationURL,
                authorityCheck: verifyImportAuthority
            )
            let value = try validator.validate(
                stagedPackageURL: destinationURL,
                cancellation: cancellation
            )
            guard value.manifest == temporaryValue.manifest,
                  value.records == temporaryValue.records,
                  value.members.keys == temporaryValue.members.keys else {
                throw BackupImportServiceError.invalidSource
            }
            try verifyImportAuthority()
            guard try itemInformation(at: destinationURL)
                    .map(FileIdentity.init) == temporaryIdentity else {
                throw BackupImportServiceError.copyFailed
            }
            return value
        } catch {
            let originalError = error
            do {
                try verifyImportAuthority()
                if try itemInformation(at: temporaryURL) != nil {
                    try cleanupOwnedPackage(
                        at: temporaryURL,
                        verifyProtection: false,
                        authorityCheck: verifyImportAuthority
                    )
                }
                try verifyImportAuthority()
                if try itemInformation(at: destinationURL) != nil {
                    try cleanupOwnedPackage(
                        at: destinationURL,
                        verifyProtection: false,
                        authorityCheck: verifyImportAuthority
                    )
                }
            } catch {
                if isProtectedDataUnavailable(originalError) {
                    throw originalError
                }
                if isProtectedDataUnavailable(error) {
                    throw error
                }
                throw BackupImportServiceError.cleanupFailed
            }
            if isProtectedDataUnavailable(originalError) {
                throw originalError
            }
            throw originalError
        }
    }

    private func validateSourceBoundary(_ sourceURL: URL) throws -> SourceBoundary {
        let root = sourceURL.standardizedFileURL
        guard root.pathExtension == "fieldrecordbackup",
              try itemInformation(at: root).map(isDirectory) == true else {
            throw BackupImportServiceError.invalidSource
        }
        let rootIdentity: BackupPackageRootIdentity
        let manifestData: Data
        do {
            rootIdentity = try BackupPackageAnchoredFile.rootIdentity(at: root)
            manifestData = try BackupPackageAnchoredFile.readRegularFile(
                "manifest.json",
                within: root,
                rootIdentity: rootIdentity,
                expectedByteCount: nil,
                maximumByteCount: Int64(archiveLimits.maximumIndexByteCount)
            )
        } catch {
            throw BackupImportServiceError.invalidSource
        }
        let manifest: V4BackupManifestV1
        do { manifest = try BackupCanonicalDecoderV1().decodeManifest(manifestData) }
        catch { throw BackupImportServiceError.invalidSource }
        try validateManifestBounds(manifest)

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
              try BackupPackageAnchoredFile.rootIdentity(at: root) == rootIdentity else {
            throw BackupImportServiceError.invalidSource
        }
        return SourceBoundary(manifest: manifest, rootIdentity: rootIdentity)
    }

    func sourceShape(
        root: URL,
        manifest: V4BackupManifestV1
    ) throws -> (Set<String>, Set<String>) {
        var sizes = [String: Int64]()
        for entry in manifest.entries {
            guard sizes.updateValue(
                Int64(entry.byteCount),
                forKey: entry.path
            ) == nil else {
                throw BackupImportServiceError.invalidSource
            }
        }
        let expectedDirectoryCount = Set(manifest.entries.compactMap { entry in
            entry.path == "records.json"
                ? nil
                : entry.path.split(separator: "/").first.map(String.init)
        }).count
        let maximumEnumeratedItemCount = manifest.entries.count
            + expectedDirectoryCount + 1
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw BackupImportServiceError.invalidSource
        }
        var files = Set<String>()
        var directories = Set<String>()
        var identities = Set<FileIdentity>()
        var enumeratedItemCount = 0
        for case let url as URL in enumerator {
            let path = try relativePath(of: url, within: root)
            guard path.utf8.count <= archiveLimits.maximumPathUTF8ByteCount,
                  enumeratedItemCount < maximumEnumeratedItemCount,
                  let information = try itemInformation(at: url) else {
                throw BackupImportServiceError.invalidSource
            }
            enumeratedItemCount += 1
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
        if let enumerationError {
            throw enumerationError
        }
        return (files, directories)
    }

    func validateManifestBounds(_ manifest: V4BackupManifestV1) throws {
        let zero = UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        ))
        let sourceIdentityIsValid: Bool
        switch (
            manifest.backupSchemaVersion,
            manifest.source.workspaceID,
            manifest.source.replicaID
        ) {
        case (1, nil, nil):
            sourceIdentityIsValid = true
        case (2, let workspaceID?, let replicaID?),
             (3, let workspaceID?, let replicaID?),
             (4, let workspaceID?, let replicaID?):
            sourceIdentityIsValid = workspaceID != zero
                && replicaID != zero
                && workspaceID != replicaID
        default:
            sourceIdentityIsValid = false
        }
        let schemaPairIsValid: Bool
        switch (
            manifest.backupSchemaVersion,
            manifest.source.persistentSchemaVersion,
            manifest.source.recordsSchemaVersion
        ) {
        case (1, 1, 1), (2, 1, 1), (2, 3, 2), (3, 4, 3),
             (4, 5, 4), (4, 6, 5), (4, 7, 6), (4, 8, 7),
             (4, 9, 8), (4, 10, 9), (4, 11, 10), (4, 12, 11):
            schemaPairIsValid = true
        default:
            schemaPairIsValid = false
        }
        guard sourceIdentityIsValid,
              schemaPairIsValid,
              manifest.entries.count <= archiveLimits.maximumEntryCount,
              manifest.declaredPayloadByteCount >= 0 else {
            throw BackupImportServiceError.invalidSource
        }
        var aggregate: Int64 = 0
        var foldedPaths = Set<String>()
        for entry in manifest.entries {
            guard validManifestRelativePath(entry.path),
                  entry.path.utf8.count <= archiveLimits.maximumPathUTF8ByteCount,
                  entry.byteCount >= 0,
                  Int64(entry.byteCount)
                    <= archiveLimits.maximumUncompressedEntryByteCount,
                  lowercaseHash(entry.sha256),
                  foldedPaths.insert(fold(entry.path)).inserted else {
                throw BackupImportServiceError.invalidSource
            }
            let (next, overflow) = aggregate.addingReportingOverflow(
                Int64(entry.byteCount)
            )
            guard !overflow,
                  next <= archiveLimits.maximumUncompressedAggregateByteCount else {
                throw BackupImportServiceError.invalidSource
            }
            aggregate = next
        }
        guard aggregate == Int64(manifest.declaredPayloadByteCount) else {
            throw BackupImportServiceError.invalidSource
        }
    }

    func validManifestRelativePath(_ value: String) -> Bool {
        guard value == value.precomposedStringWithCanonicalMapping,
              !value.hasPrefix("/"),
              !value.contains("\\"),
              value.removingPercentEncoding == value else {
            return false
        }
        let components = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !components.isEmpty && components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
                && !component.unicodeScalars.contains(where: {
                    $0.value < 0x20 || $0.value == 0x7f
                })
        }
    }

    func fold(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    func lowercaseHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    func prepareStagingDirectory() throws {
        let importAuthority = try PinnedImportAuthority.open(
            stagingURL: stagingDirectoryURL,
            createMissing: true
        )
        let verifyImportAuthority = {
            try self.requireCurrentGeneration()
            try importAuthority.verify()
        }
        try verifyImportAuthority()
        let restoreURL = stagingDirectoryURL.deletingLastPathComponent()
        for directory in [restoreURL, stagingDirectoryURL] {
            do {
                try ProtectedFilePolicyV1.applyAndVerify(
                    .stagingDirectory,
                    at: directory,
                    authorityCheck: verifyImportAuthority
                )
            } catch let failure as ProtectedFilePolicyError {
                throw failure
            } catch {
                throw BackupImportServiceError.invalidGeneration
            }
        }
        try verifyImportAuthority()
    }

    func protectStagedPackage(
        at packageURL: URL,
        authorityCheck: @escaping () throws -> Void = {}
    ) throws {
        let packageURL = packageURL.standardizedFileURL
        let parentURL = packageURL.deletingLastPathComponent()
        try authorityCheck()
        let parentDescriptor = try openPinnedDirectory(at: parentURL)
        defer { _ = Darwin.close(parentDescriptor.descriptor) }
        let packageDescriptor = Darwin.openat(
            parentDescriptor.descriptor,
            packageURL.lastPathComponent,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard packageDescriptor >= 0 else {
            throw BackupImportServiceError.copyFailed
        }
        defer { _ = Darwin.close(packageDescriptor) }
        let packageIdentity = try directoryIdentity(packageDescriptor)
        func verifyAuthority() throws {
            try authorityCheck()
            try requireCurrentGeneration()
            try verifyDirectoryPath(parentURL, expected: parentDescriptor.identity)
            try verifyPackage(
                packageDescriptor,
                parent: parentDescriptor.descriptor,
                name: packageURL.lastPathComponent,
                expected: packageIdentity
            )
        }
        var enumerationError: Error?
        try verifyAuthority()
        try ProtectedFilePolicyV1.applyAndVerify(
            .restoreStaging,
            at: packageURL,
            authorityCheck: verifyAuthority
        )
        guard let enumerator = fileManager.enumerator(
            at: packageURL,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw BackupImportServiceError.copyFailed
        }
        for case let url as URL in enumerator {
            try verifyAuthority()
            guard let information = try itemInformation(at: url) else {
                throw BackupImportServiceError.copyFailed
            }
            let kind: OwnedFileKindV1
            switch information.st_mode & S_IFMT {
            case S_IFDIR:
                kind = .stagingDirectory
            case S_IFREG:
                kind = .stagingFile
            default:
                throw BackupImportServiceError.invalidSource
            }
            let identity = FileIdentity(information)
            let relative = try relativePath(of: url, within: packageURL)
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: relative,
                within: packageURL,
                authorityCheck: verifyAuthority
            )
            try verifyAuthority()
            guard try itemInformation(at: url).map(FileIdentity.init) == identity else {
                throw BackupImportServiceError.cleanupFailed
            }
        }
        if let enumerationError {
            throw enumerationError
        }
        try verifyAuthority()
    }

    func cleanupOwnedPackage(
        at packageURL: URL,
        verifyProtection: Bool = true,
        authorityCheck: @escaping () throws -> Void = {}
    ) throws {
        let value = packageURL.standardizedFileURL
        let parent = value.deletingLastPathComponent()
        guard value.pathExtension == "fieldrecordbackup" else {
            throw BackupImportServiceError.cleanupFailed
        }
        let rawStem = value.deletingPathExtension().lastPathComponent
        let stem = rawStem.hasSuffix("-tmp")
            ? String(rawStem.dropLast(4))
            : rawStem
        guard parent == stagingDirectoryURL,
              let id = UUID(uuidString: stem),
              id.uuidString.lowercased() == stem else {
            throw BackupImportServiceError.cleanupFailed
        }
        let importAuthority = try PinnedImportAuthority.open(
            stagingURL: stagingDirectoryURL
        )
        let verifyImportAuthority = {
            try self.requireCurrentGeneration()
            try importAuthority.verify()
            try authorityCheck()
        }
        try verifyImportAuthority()
        guard let information = try itemInformation(at: value) else { return }
        guard isDirectory(information),
              try itemInformation(at: parent).map(isDirectory) == true else {
            throw BackupImportServiceError.cleanupFailed
        }
        if verifyProtection {
            try protectStagedPackage(
                at: value,
                authorityCheck: verifyImportAuthority
            )
        }
        try verifyImportAuthority()
        let parentDescriptor = (
            descriptor: importAuthority.stagingDescriptor,
            identity: importAuthority.stagingIdentity
        )
        try verifyDirectoryPath(
            parent,
            expected: parentDescriptor.identity
        )
        try verifyImportAuthority()
        let packageDescriptor = Darwin.openat(
            parentDescriptor.descriptor,
            value.lastPathComponent,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard packageDescriptor >= 0 else {
            throw BackupImportServiceError.cleanupFailed
        }
        defer { _ = Darwin.close(packageDescriptor) }
        let packageIdentity = try directoryIdentity(packageDescriptor)
        try verifyPackage(
            packageDescriptor,
            parent: parentDescriptor.descriptor,
            name: value.lastPathComponent,
            expected: packageIdentity
        )
        try verifyImportAuthority()
        try removeOwnedPackageContents(
            root: value,
            packageDescriptor: packageDescriptor,
            parentDescriptor: parentDescriptor.descriptor,
            packageName: value.lastPathComponent,
            packageIdentity: packageIdentity,
            authorityCheck: verifyImportAuthority
        )
        try verifyImportAuthority()
        try verifyDirectoryPath(
            parent,
            expected: parentDescriptor.identity
        )
        try verifyPackage(
            packageDescriptor,
            parent: parentDescriptor.descriptor,
            name: value.lastPathComponent,
            expected: packageIdentity
        )
        try verifyImportAuthority()
        guard Darwin.unlinkat(
            parentDescriptor.descriptor,
            value.lastPathComponent,
            AT_REMOVEDIR
        ) == 0,
              Darwin.fsync(parentDescriptor.descriptor) == 0 else {
            throw BackupImportServiceError.cleanupFailed
        }
        try verifyImportAuthority()
        try verifyDirectoryPath(
            parent,
            expected: parentDescriptor.identity
        )
        try verifyImportAuthority()
        guard try itemInformation(at: value) == nil else {
            throw BackupImportServiceError.cleanupFailed
        }
    }

    private func removeOwnedPackageContents(
        root: URL,
        packageDescriptor: Int32,
        parentDescriptor: Int32,
        packageName: String,
        packageIdentity: FileIdentity,
        authorityCheck: () throws -> Void = {}
    ) throws {
        try authorityCheck()
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw BackupImportServiceError.cleanupFailed
        }
        var identities = [String: FileIdentity]()
        var directories = Set<String>()
        for case let url as URL in enumerator {
            try authorityCheck()
            let relative = try relativePath(of: url, within: root)
            guard let information = try itemInformation(at: url) else {
                throw BackupImportServiceError.cleanupFailed
            }
            let type = information.st_mode & S_IFMT
            guard type == S_IFDIR || type == S_IFREG else {
                throw BackupImportServiceError.cleanupFailed
            }
            if type == S_IFREG {
                guard information.st_nlink == 1 else {
                    throw BackupImportServiceError.cleanupFailed
                }
            } else {
                directories.insert(relative)
            }
            guard identities.updateValue(
                FileIdentity(information),
                forKey: relative
            ) == nil else {
                throw BackupImportServiceError.cleanupFailed
            }
        }
        if let enumerationError {
            throw enumerationError
        }
        let paths = identities.keys.sorted {
            let leftDepth = $0.split(separator: "/").count
            let rightDepth = $1.split(separator: "/").count
            return leftDepth == rightDepth ? $0 > $1 : leftDepth > rightDepth
        }
        for relative in paths {
            try authorityCheck()
            try verifyPackage(
                packageDescriptor,
                parent: parentDescriptor,
                name: packageName,
                expected: packageIdentity
            )
            let components = relative.split(separator: "/").map(String.init)
            guard let name = components.last else {
                throw BackupImportServiceError.cleanupFailed
            }
            let parentComponents = Array(components.dropLast())
            let opened = try openDirectory(
                packageDescriptor,
                components: parentComponents
            )
            defer {
                for descriptor in opened.1.reversed() {
                    _ = Darwin.close(descriptor)
                }
            }
            guard let expected = identities[relative],
                  try itemIdentity(
                      parent: opened.0,
                      name: name
                  ) == expected else {
                throw BackupImportServiceError.cleanupFailed
            }
            let flags: Int32 = directories.contains(relative)
                ? AT_REMOVEDIR
                : 0
            guard Darwin.unlinkat(opened.0, name, flags) == 0,
                  Darwin.fsync(opened.0) == 0 else {
                throw BackupImportServiceError.cleanupFailed
            }
            try authorityCheck()
        }
    }

    private func openPinnedDirectory(
        at url: URL
    ) throws -> (descriptor: Int32, identity: FileIdentity) {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw BackupImportServiceError.cleanupFailed
        }
        do {
            let identity = try directoryIdentity(descriptor)
            return (descriptor, identity)
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    private func directoryIdentity(_ descriptor: Int32) throws -> FileIdentity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFDIR else {
            throw BackupImportServiceError.cleanupFailed
        }
        return FileIdentity(information)
    }

    private func verifyDirectoryPath(
        _ url: URL,
        expected: FileIdentity
    ) throws {
        guard try itemInformation(at: url).map(FileIdentity.init) == expected else {
            throw BackupImportServiceError.cleanupFailed
        }
    }

    private func verifyPackage(
        _ descriptor: Int32,
        parent: Int32,
        name: String,
        expected: FileIdentity
    ) throws {
        guard try directoryIdentity(descriptor) == expected,
              try itemIdentity(parent: parent, name: name) == expected else {
            throw BackupImportServiceError.cleanupFailed
        }
    }

    private func openDirectory(
        _ root: Int32,
        components: [String]
    ) throws -> (descriptor: Int32, opened: [Int32]) {
        var current = root
        var opened = [Int32]()
        for component in components {
            let descriptor = Darwin.openat(
                current,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                for value in opened.reversed() { _ = Darwin.close(value) }
                throw BackupImportServiceError.cleanupFailed
            }
            opened.append(descriptor)
            current = descriptor
        }
        return (current, opened)
    }

    private func itemIdentity(
        parent: Int32,
        name: String
    ) throws -> FileIdentity {
        var information = stat()
        guard Darwin.fstatat(
            parent,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
              (information.st_mode & S_IFMT) != S_IFLNK else {
            throw BackupImportServiceError.cleanupFailed
        }
        return FileIdentity(information)
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

    func isProtectedDataUnavailable(_ error: Error) -> Bool {
        ProtectedFilePolicyV1.isProtectedDataUnavailable(error)
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

    func isRegularFile(_ information: stat) -> Bool {
        (information.st_mode & S_IFMT) == S_IFREG
            && information.st_nlink == 1
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

import Darwin
import Foundation
import PDFKit

enum BackupPackageValidationErrorV1: Error, Equatable {
    case invalidPackage
}

struct BackupValidationSummaryV1: Equatable, Sendable {
    let incomingSignCount: Int
    let incomingReportCount: Int
    let incomingPhotoCount: Int
    let exportedAt: Date
    let declaredPayloadByteCount: Int
    let packs: [V4BackupPackV1]
    let consumedRootCount: Int
    let liveSlotCount: Int
    let tombstonedSlotCount: Int
}

enum BackupPackageCompatibilityPostureV1: String, Sendable {
    case frozenLegacyCallersOnly = "FROZEN_LEGACY_CALLERS_ONLY"
}

enum BackupPackageValidationRouteV1: Sendable {
    case live(WorkspacePackageLifecycleProfileRegistryV1)
    case expiringCompatibility(SignPack, BackupPackageCompatibilityPostureV1)
}

struct ValidatedV4BackupPackageV1: Equatable, Sendable {
    let stagedPackageURL: URL
    let manifest: V4BackupManifestV1
    let records: V4BackupRecordsV1
    let members: ValidatedV4BackupMembersV1
    let summary: BackupValidationSummaryV1
}

struct ValidatedV4BackupMembersV1: Equatable, @unchecked Sendable {
    struct Descriptor: Equatable, Sendable {
        let byteCount: Int64
        let sha256: String
    }

    let rootURL: URL
    let rootIdentity: BackupPackageRootIdentity
    let descriptors: [String: Descriptor]
    let maximumMemberByteCount: Int64

    var keys: Set<String> { Set(descriptors.keys) }

    subscript(path: String) -> Data? {
        guard let descriptor = descriptors[path],
              descriptor.byteCount >= 0,
              descriptor.byteCount <= maximumMemberByteCount,
              let data = try? BackupPackageAnchoredFile.readRegularFile(
                  path,
                  within: rootURL,
                  rootIdentity: rootIdentity,
                  expectedByteCount: descriptor.byteCount,
                  maximumByteCount: maximumMemberByteCount
              ),
              CanonicalJSONV1.sha256(data) == descriptor.sha256 else {
            return nil
        }
        return data
    }
}

struct BackupPackageRootIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}

enum BackupPackageAnchoredFile {
    static func rootIdentity(at rootURL: URL) throws -> BackupPackageRootIdentity {
        let descriptor = try openRoot(rootURL)
        defer { Darwin.close(descriptor) }
        return try identity(of: descriptor)
    }

    static func readRegularFile(
        _ relativePath: String,
        within rootURL: URL,
        rootIdentity: BackupPackageRootIdentity,
        expectedByteCount: Int64? = nil,
        maximumByteCount: Int64 = Int64.max
    ) throws -> Data {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }

        var descriptor = try openRoot(rootURL)
        defer { Darwin.close(descriptor) }
        guard try identity(of: descriptor) == rootIdentity else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        for component in components.dropLast() {
            let child = Darwin.openat(
                descriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard child >= 0 else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            Darwin.close(descriptor)
            descriptor = child
        }
        guard let leaf = components.last else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        let fileDescriptor = Darwin.openat(
            descriptor,
            leaf,
            O_RDONLY | O_NOFOLLOW
        )
        guard fileDescriptor >= 0 else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        let handle = FileHandle(
            fileDescriptor: fileDescriptor,
            closeOnDealloc: true
        )
        defer { try? handle.close() }
        var information = stat()
        guard Darwin.fstat(fileDescriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,
              information.st_size <= maximumByteCount,
              expectedByteCount.map({ $0 == information.st_size }) ?? true,
              information.st_size <= Int64(Int.max) else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        var data = Data()
        let bufferByteCount = 64 * 1_024
        while data.count < Int(information.st_size) {
            let remaining = Int(information.st_size) - data.count
            guard let chunk = try handle.read(
                upToCount: min(bufferByteCount, remaining)
            ), !chunk.isEmpty else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            data.append(chunk)
        }
        guard data.count == Int(information.st_size),
              try handle.read(upToCount: 1)?.isEmpty != false else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        var finalInformation = stat()
        guard Darwin.fstat(fileDescriptor, &finalInformation) == 0,
              finalInformation.st_dev == information.st_dev,
              finalInformation.st_ino == information.st_ino,
              finalInformation.st_nlink == information.st_nlink,
              finalInformation.st_size == information.st_size,
              finalInformation.st_mtimespec.tv_sec == information.st_mtimespec.tv_sec,
              finalInformation.st_mtimespec.tv_nsec == information.st_mtimespec.tv_nsec,
              finalInformation.st_ctimespec.tv_sec == information.st_ctimespec.tv_sec,
              finalInformation.st_ctimespec.tv_nsec == information.st_ctimespec.tv_nsec else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        return data
    }

    private static func openRoot(_ rootURL: URL) throws -> Int32 {
        let descriptor = Darwin.open(
            rootURL.standardizedFileURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        return descriptor
    }

    private static func identity(
        of descriptor: Int32
    ) throws -> BackupPackageRootIdentity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFDIR else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        return BackupPackageRootIdentity(
            device: information.st_dev,
            inode: information.st_ino
        )
    }
}

struct BackupPackageValidatorV1: Sendable {
    private let fileManager: FileManager
    private let profileRoute: BackupPackageValidationRouteV1
    private let limits: StreamingArchiveLimitsV1

    init(
        route: BackupPackageValidationRouteV1,
        fileManager: FileManager = .default,
        limits: StreamingArchiveLimitsV1 = .card17
    ) {
        self.fileManager = fileManager
        self.profileRoute = route
        self.limits = limits
    }

    init(
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1,
        fileManager: FileManager = .default,
        limits: StreamingArchiveLimitsV1 = .card17
    ) {
        self.fileManager = fileManager
        self.profileRoute = .live(profileRegistry)
        self.limits = limits
    }

    init(
        fileManager: FileManager = .default,
        signPack: SignPack = .illuminatedSignV1,
        limits: StreamingArchiveLimitsV1 = .card17,
        compatibilityPosture: BackupPackageCompatibilityPostureV1 = .frozenLegacyCallersOnly
    ) {
        self.fileManager = fileManager
        self.profileRoute = .expiringCompatibility(signPack, compatibilityPosture)
        self.limits = limits
    }

    func validate(
        stagedPackageURL: URL,
        cancellation: StreamingArchiveCancellationV1 = .none
    ) throws -> ValidatedV4BackupPackageV1 {
        do {
            return try validatePackage(
                stagedPackageURL: stagedPackageURL,
                cancellation: cancellation
            )
        } catch let failure as StreamingArchiveFailureV1
            where failure == .cancelled {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as GenerationLeaseRegistryFailureV1 {
            throw failure
        } catch {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }

    /// Runs descriptor-pinned hashing and semantic validation on a utility
    /// executor. Existing synchronous callers retain their exact behavior.
    func validateOffMain(
        stagedPackageURL: URL,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> ValidatedV4BackupPackageV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let taskContext = context
        let value = try await BackupOffMainWorkV1.run {
            try self.validate(
                stagedPackageURL: stagedPackageURL,
                cancellation: StreamingArchiveCancellationV1 {
                    guard !Task.isCancelled else {
                        throw StreamingArchiveFailureV1.cancelled
                    }
                    try taskContext?.validateGenerationLease()
                }
            )
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }
}

private extension BackupPackageValidatorV1 {
    func resolvedProfileRegistry() throws
        -> WorkspacePackageLifecycleProfileRegistryV1 {
        switch profileRoute {
        case let .live(registry):
            return registry
        case let .expiringCompatibility(package, posture):
            guard posture == .frozenLegacyCallersOnly else { throw invalid() }
            do {
                return try WorkspacePackageLifecycleCompatibilityV1
                    .legacyV3Registry(package: package)
            } catch {
                throw invalid()
            }
        }
    }

    func validatePackage(
        stagedPackageURL: URL,
        cancellation: StreamingArchiveCancellationV1
    ) throws -> ValidatedV4BackupPackageV1 {
        try cancellation.checkpoint()
        let root = stagedPackageURL.standardizedFileURL
        guard stagedPackageURL.isFileURL,
              root.pathExtension == "fieldrecordbackup",
              root.lastPathComponent == root.lastPathComponent.precomposedStringWithCanonicalMapping,
              try itemType(root) == .directory else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        let rootIdentity = try BackupPackageAnchoredFile.rootIdentity(at: root)
        let decoder = BackupCanonicalDecoderV1()
        let manifestValue: (
            manifest: V4BackupManifestV1,
            descriptor: ValidatedV4BackupMembersV1.Descriptor
        ) = try {
            let manifestData = try anchoredRead(
                "manifest.json",
                root: root,
                identity: rootIdentity,
                expectedByteCount: nil,
                maximumByteCount: Int64(limits.maximumIndexByteCount)
            )
            return (
                try decoder.decodeManifest(manifestData),
                .init(
                    byteCount: Int64(manifestData.count),
                    sha256: CanonicalJSONV1.sha256(manifestData)
                )
            )
        }()
        let manifest = manifestValue.manifest
        try validateManifestBounds(manifest)
        let expectedFiles = Set(["manifest.json"] + manifest.entries.map(\.path))
        let expectedDirectories = Set(manifest.entries.compactMap { entry in
            entry.path == "records.json" ? nil : entry.path.split(separator: "/").first.map(String.init)
        })
        let enumerated = try enumerate(root: root)
        guard enumerated.files == expectedFiles,
              enumerated.directories == expectedDirectories,
              try BackupPackageAnchoredFile.rootIdentity(at: root) == rootIdentity else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }

        var descriptors = [
            "manifest.json": manifestValue.descriptor
        ]
        for entry in manifest.entries {
            guard descriptors.updateValue(
                .init(byteCount: Int64(entry.byteCount), sha256: entry.sha256),
                forKey: entry.path
            ) == nil else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        }
        let members = ValidatedV4BackupMembersV1(
            rootURL: root,
            rootIdentity: rootIdentity,
            descriptors: descriptors,
            maximumMemberByteCount: limits.maximumUncompressedEntryByteCount
        )
        for entry in manifest.entries {
            try cancellation.checkpoint()
            guard let bytes = members[entry.path] else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            guard bytes.count == entry.byteCount,
                  CanonicalJSONV1.sha256(bytes) == entry.sha256 else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        }
        guard members.keys.count == expectedFiles.count else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        let records: V4BackupRecordsV1 = try {
            guard let recordsData = members["records.json"] else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            return try decoder.decodeRecords(recordsData)
        }()
        try cancellation.checkpoint()
        try validateGraph(records, manifest: manifest)
        try cancellation.checkpoint()
        try validateOwnedMembers(
            records,
            manifest: manifest,
            members: members,
            cancellation: cancellation
        )
        try cancellation.checkpoint()
        try validateReports(
            records,
            members: members,
            cancellation: cancellation
        )
        try cancellation.checkpoint()
        guard try BackupPackageAnchoredFile.rootIdentity(at: root) == rootIdentity else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }

        let liveSlots = records.packets.filter { $0.currentRecordID != nil }.count
        let tombstones = records.packets.filter { $0.currentRecordID == nil }.count
        return ValidatedV4BackupPackageV1(
            stagedPackageURL: root,
            manifest: manifest,
            records: records,
            members: members,
            summary: .init(
                incomingSignCount: records.assets.count,
                incomingReportCount: records.reports.count,
                incomingPhotoCount: records.evidenceFiles.count,
                exportedAt: manifest.exportedAt,
                declaredPayloadByteCount: manifest.declaredPayloadByteCount,
                packs: manifest.packs,
                consumedRootCount: manifest.consumedEvaluationRootIDs.count,
                liveSlotCount: liveSlots,
                tombstonedSlotCount: tombstones
            )
        )
    }

    struct Enumeration {
        var files = Set<String>()
        var directories = Set<String>()
    }

    enum ItemType { case directory, regular }

    func enumerate(root: URL) throws -> Enumeration {
        var result = Enumeration()
        let roots = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        )
        var folded = Set<String>()
        for value in roots {
            let name = value.lastPathComponent
            try validateComponent(name)
            guard folded.insert(fold(name)).inserted else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            switch try itemType(value) {
            case .regular:
                guard name == "manifest.json" || name == "records.json",
                      result.files.insert(name).inserted else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
            case .directory:
                guard ["media", "thumbnails", "snapshots", "pdfs"].contains(name),
                      result.directories.insert(name).inserted else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
                let children = try fileManager.contentsOfDirectory(
                    at: value,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                guard !children.isEmpty else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
                var childFolded = Set<String>()
                for child in children {
                    let childName = child.lastPathComponent
                    try validateComponent(childName)
                    guard childFolded.insert(fold(childName)).inserted,
                          try itemType(child) == .regular else {
                        throw BackupPackageValidationErrorV1.invalidPackage
                    }
                    let relative = "\(name)/\(childName)"
                    guard result.files.insert(relative).inserted else {
                        throw BackupPackageValidationErrorV1.invalidPackage
                    }
                }
            }
        }
        return result
    }

    func itemType(_ url: URL) throws -> ItemType {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        switch information.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFREG:
            guard information.st_nlink == 1 else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            return .regular
        default:
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }

    func validateComponent(_ value: String) throws {
        guard !value.isEmpty,
              value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"),
              value == value.precomposedStringWithCanonicalMapping,
              !value.unicodeScalars.contains(where: {
                  $0.value < 0x20 || $0.value == 0x7f
              }),
              value.removingPercentEncoding == value else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }

    func fold(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    func anchoredRead(
        _ path: String,
        root: URL,
        identity: BackupPackageRootIdentity,
        expectedByteCount: Int64? = nil,
        maximumByteCount: Int64 = Int64.max
    ) throws -> Data {
        guard validRelativePath(path) else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        return try BackupPackageAnchoredFile.readRegularFile(
            path,
            within: root,
            rootIdentity: identity,
            expectedByteCount: expectedByteCount,
            maximumByteCount: maximumByteCount
        )
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
        let sourceGenerationIsValid: Bool
        if manifest.source.recordsSchemaVersion >= 5 {
            sourceGenerationIsValid = manifest.source.sourceGenerationID.map {
                $0 != zero && $0 != manifest.source.workspaceID
                    && $0 != manifest.source.replicaID
            } ?? false
        } else {
            sourceGenerationIsValid = manifest.source.sourceGenerationID == nil
        }
        let schemaPairIsValid: Bool
        switch (
            manifest.backupSchemaVersion,
            manifest.source.persistentSchemaVersion,
            manifest.source.recordsSchemaVersion
        ) {
        case (1, 1, 1), (2, 1, 1), (2, 3, 2), (3, 4, 3),
             (4, 5, 4), (4, 6, 5), (4, 7, 6):
            schemaPairIsValid = true
        default:
            schemaPairIsValid = false
        }
        guard sourceIdentityIsValid, sourceGenerationIsValid,
              schemaPairIsValid,
              manifest.entries.count <= limits.maximumEntryCount,
              manifest.declaredPayloadByteCount >= 0 else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        var aggregate: Int64 = 0
        var foldedPaths = Set<String>()
        for entry in manifest.entries {
            guard validRelativePath(entry.path),
                  entry.path.utf8.count <= limits.maximumPathUTF8ByteCount,
                  entry.byteCount >= 0,
                  Int64(entry.byteCount) <= limits.maximumUncompressedEntryByteCount,
                  lowercaseHash(entry.sha256),
                  foldedPaths.insert(fold(entry.path)).inserted else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            let (next, overflow) = aggregate.addingReportingOverflow(
                Int64(entry.byteCount)
            )
            guard !overflow,
                  next <= limits.maximumUncompressedAggregateByteCount else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            aggregate = next
        }
        guard aggregate == Int64(manifest.declaredPayloadByteCount) else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }

    func validRelativePath(_ value: String) -> Bool {
        guard value == value.precomposedStringWithCanonicalMapping,
              !value.hasPrefix("/"), !value.contains("\\"),
              value.removingPercentEncoding == value else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
                && !component.unicodeScalars.contains(where: {
                    $0.value < 0x20 || $0.value == 0x7f
                })
        }
    }
}

private extension BackupPackageValidatorV1 {
    func releaseIdentity(
        packageID: String,
        schemaVersion: Int,
        contentVersion: Int
    ) throws -> PackageReleaseIdentityV1 {
        do {
            return try PackageReleaseIdentityV1(
                packageID: packageID,
                schemaVersion: schemaVersion,
                contentVersion: contentVersion
            )
        } catch {
            throw invalid()
        }
    }

    func releaseIdentity(
        for asset: V4BackupAssetDTO
    ) throws -> PackageReleaseIdentityV1 {
        try releaseIdentity(
            packageID: asset.packID,
            schemaVersion: asset.packSchemaVersion,
            contentVersion: asset.packContentVersion
        )
    }

    func releaseIdentity(
        for record: V4BackupWorkflowRecordDTO
    ) throws -> PackageReleaseIdentityV1 {
        try releaseIdentity(
            packageID: record.packID,
            schemaVersion: record.packSchemaVersion,
            contentVersion: record.packContentVersion
        )
    }

    func profile(
        packageID: String,
        schemaVersion: Int,
        contentVersion: Int
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        do {
            return try resolvedProfileRegistry().resolve(releaseIdentity(
                packageID: packageID,
                schemaVersion: schemaVersion,
                contentVersion: contentVersion
            ))
        } catch {
            throw invalid()
        }
    }

    func profile(
        _ value: V4BackupPackV1
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        try profile(
            packageID: value.id,
            schemaVersion: value.schemaVersion,
            contentVersion: value.contentVersion
        )
    }

    func profile(
        for asset: V4BackupAssetDTO
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        try resolvedProfileRegistry().resolve(releaseIdentity(for: asset))
    }

    func profile(
        for record: V4BackupWorkflowRecordDTO
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        try resolvedProfileRegistry().resolve(releaseIdentity(for: record))
    }

    func outcomeProfile(
        _ key: String?,
        in stage: WorkspacePackageStageProfileV1
    ) throws -> WorkspacePackageOutcomeProfileV1 {
        guard let key,
              let value = stage.outcomes.first(where: { $0.key == key }) else {
            throw invalid()
        }
        return value
    }

    func validateGraph(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        try KernelBackupRestoreRegistryV4.validate()
        let kernelSchema = try KernelPersistenceV4Schema.descriptor()
        guard kernelSchema.runtimePosture == .dormantStatic,
              !kernelSchema.activationEnabled else { throw invalid() }
        try validateDeletionLedger(records, manifest: manifest)
        try validateObservationAndTime(records)
        try validateLocationRecords(records, manifest: manifest)
        let savedSmartViews: [SavedSmartViewDescriptorV1]
        do {
            savedSmartViews = try records.savedSmartViews.map { try $0.descriptor() }
        } catch {
            throw invalid()
        }
        guard records.recordsSchemaVersion < 6
                ? savedSmartViews.isEmpty
                : (records.recordsSchemaVersion == 6
                    && savedSmartViews.allSatisfy({
                        $0.workspaceID == manifest.source.workspaceID
                    })) else {
            throw invalid()
        }
        let allIDs = records.sites.map(\.id) + records.assets.map(\.id)
            + records.workflowRecords.map(\.id) + records.evidenceFiles.map(\.id)
            + records.issues.map(\.id) + records.packets.map(\.id)
            + records.reports.map(\.id) + records.assetCompositionEdges.map(\.id)
            + records.assetCompositionEvents.map(\.id)
            + records.assetPlacementEvents.map(\.id)
            + records.locationHierarchyEvents.map(\.id)
            + records.locationMigrationReceipts.map(\.id)
            + records.locationNodes.map(\.id)
            + records.savedSmartViews.map(\.id)
        guard Set(allIDs).count == allIDs.count else { throw invalid() }
        let sites = Dictionary(uniqueKeysWithValues: records.sites.map { ($0.id, $0) })
        let assets = Dictionary(uniqueKeysWithValues: records.assets.map { ($0.id, $0) })
        let workflow = Dictionary(uniqueKeysWithValues: records.workflowRecords.map { ($0.id, $0) })
        let issues = Dictionary(uniqueKeysWithValues: records.issues.map { ($0.id, $0) })
        let packets = Dictionary(uniqueKeysWithValues: records.packets.map { ($0.id, $0) })
        let reports = Dictionary(uniqueKeysWithValues: records.reports.map { ($0.id, $0) })
        let declaredProfiles = try manifest.packs.map { try profile($0) }
        guard Set(declaredProfiles.map(\.release)).count == declaredProfiles.count else {
            throw invalid()
        }
        guard records.sites.allSatisfy({ site in
                  site.schemaVersion == 1
                    && site.updatedAt >= site.createdAt
                    && validRequiredTrimmed(site.label, maximum: .max)
                    && (site.address.map({
                        validRequiredTrimmed($0, maximum: .max)
                    }) ?? true)
                    && (site.timeZoneID.map({ value in
                        value == value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ) && TimeZone.knownTimeZoneIdentifiers.contains(value)
                    }) ?? true)
              }),
              records.evidenceFiles.allSatisfy({ $0.schemaVersion == 1 }),
              records.issues.allSatisfy({ $0.schemaVersion == 1 }),
              records.packets.allSatisfy({ $0.schemaVersion == 1 }),
              records.reports.allSatisfy({ $0.schemaVersion == 1 }),
              records.workflowRecords.allSatisfy({ $0.schemaVersion == 1 }) else {
            throw invalid()
        }

        for asset in records.assets {
            _ = try profile(
                packageID: asset.packID,
                schemaVersion: asset.packSchemaVersion,
                contentVersion: asset.packContentVersion
            )
            guard asset.schemaVersion == 1,
                  asset.updatedAt >= asset.createdAt,
                  validRequiredTrimmed(asset.label, maximum: .max),
                  sites[asset.siteID] != nil else { throw invalid() }
        }

        for record in records.workflowRecords {
            guard let asset = assets[record.assetID] else { throw invalid() }
            let lifecycle = try profile(for: record)
            guard lifecycle.release == (try releaseIdentity(for: asset)),
                  let kind = WorkflowRevisionKind(rawValue: record.revisionKind),
                  WorkflowStage(rawValue: record.stage) != nil,
                  let state = WorkflowState(rawValue: record.state),
                  record.pdfTemplateID == lifecycle.pdfTemplate.id,
                  record.pdfTemplateVersion == lifecycle.pdfTemplate.version,
                  record.parentRecordID.map({ workflow[$0]?.assetID == record.assetID }) ?? true,
                  record.issueID.map({ issues[$0]?.assetID == record.assetID }) ?? true else {
                throw invalid()
            }
            switch state {
            case .draft:
                guard record.completedAt == nil, record.packetID == nil,
                      record.finalizationMutationID == nil,
                      record.outcomeKey == nil,
                      validDraftSemantics(
                          record,
                          profile: lifecycle,
                          workflow: workflow,
                          issues: issues
                      ) else {
                    throw invalid()
                }
            case .completed:
                guard record.completedAt.map({ $0 >= record.startedAt }) == true,
                      record.finalizationMutationID != nil,
                      record.outcomeKey != nil,
                      record.draftStepKey == nil,
                      validCompletedSemantics(record, profile: lifecycle),
                      record.packetID.map({ packets[$0] != nil }) ?? true else {
                    throw invalid()
                }
            }
            guard let root = workflow[record.recordRevisionRootID],
                  root.assetID == record.assetID,
                  root.revisionKind == WorkflowRevisionKind.original.rawValue,
                  root.recordRevisionRootID == root.id,
                  root.revisesRecordID == nil,
                  root.evidenceSourceRecordID == nil else { throw invalid() }
            switch kind {
            case .original:
                guard record.recordRevisionRootID == record.id,
                      record.revisesRecordID == nil,
                      record.evidenceSourceRecordID == nil else { throw invalid() }
            case .clericalCorrection:
                guard let revisedID = record.revisesRecordID,
                      let revised = workflow[revisedID],
                      record.recordRevisionRootID != record.id,
                      record.evidenceSourceRecordID == record.recordRevisionRootID,
                      validCorrection(record, prior: revised, root: root) else {
                    throw invalid()
                }
            }
        }
        try requireAcyclic(records.workflowRecords, id: \.id, next: \.parentRecordID)
        try requireAcyclic(records.workflowRecords, id: \.id, next: \.revisesRecordID)
        guard unique(records.workflowRecords.compactMap(\.revisesRecordID)),
              unique(records.workflowRecords.compactMap(\.finalizationMutationID)),
              records.assets.allSatisfy({ asset in
                  records.workflowRecords.filter {
                      $0.assetID == asset.id
                        && $0.state == WorkflowState.draft.rawValue
                  }.count <= 1
              }) else {
            throw invalid()
        }

        for evidence in records.evidenceFiles {
            let id = uuid(evidence.id)
            guard let owner = workflow[evidence.recordID] else { throw invalid() }
            let lifecycle = try profile(for: owner)
            let allowedPurposes = Set(lifecycle.package.evidencePurposes.map(\.key))
            guard
                  owner.revisionKind == WorkflowRevisionKind.original.rawValue,
                  evidence.createdAt >= owner.startedAt,
                  owner.completedAt.map({ evidence.createdAt <= $0 }) ?? true,
                  allowedPurposes.contains(evidence.purposeKey),
                  evidence.mimeType == "image/jpeg",
                  evidence.byteCount >= 0, evidence.thumbnailByteCount >= 0,
                  evidence.relativePath == "evidence/\(id)/original.jpg",
                  evidence.thumbnailRelativePath == "evidence/\(id)/thumbnail.jpg",
                  lowercaseHash(evidence.sha256), lowercaseHash(evidence.thumbnailSHA256) else {
                throw invalid()
            }
        }
        for record in records.workflowRecords {
            let owned = records.evidenceFiles.filter { $0.recordID == record.id }
            guard unique(owned.map(\.purposeKey)) else { throw invalid() }
            let lifecycle = try profile(for: record)
            if record.state == WorkflowState.completed.rawValue {
                let observed = Set(owned.map(\.purposeKey))
                switch WorkflowStage(rawValue: record.stage) {
                case .check, .recheck:
                    let stage = try lifecycle.stage(record.stage)
                    let required = Set(lifecycle.evidencePurposeKeys(for: .captureRequired))
                    let allowed = required.union(
                        lifecycle.evidencePurposeKeys(for: .captureSupplementary)
                    )
                    guard observed.isSubset(of: allowed) else { throw invalid() }
                    let outcome = try outcomeProfile(record.outcomeKey, in: stage)
                    if outcome.role == .couldNotVerify {
                        guard observed.isSubset(of: required) else { throw invalid() }
                    } else if record.revisionKind == WorkflowRevisionKind.original.rawValue {
                        guard required.isSubset(of: observed) else { throw invalid() }
                    }
                case .work:
                    let allowed = Set(
                        lifecycle.evidencePurposeKeys(for: .workSupplementary)
                    )
                    guard observed.isSubset(of: allowed) else { throw invalid() }
                case nil:
                    throw invalid()
                }
            } else if record.state == WorkflowState.draft.rawValue {
                guard validDraftEvidence(
                    record,
                    profile: lifecycle,
                    owned: owned
                ) else {
                    throw invalid()
                }
            }
        }
        for issue in records.issues {
            guard let asset = assets[issue.assetID] else { throw invalid() }
            let lifecycle = try profile(for: asset)
            let package = lifecycle.package
            let openingRole = try lifecycle.stage(
                workflow[issue.openedByRecordID]?.stage ?? ""
            ).outcomes.first(where: {
                $0.key == workflow[issue.openedByRecordID]?.outcomeKey
            })?.role
            guard
                  let opened = workflow[issue.openedByRecordID],
                  opened.assetID == issue.assetID,
                  package.issueLabels.filter({
                      $0.key == issue.labelKey
                        && $0.display == issue.labelDisplaySnapshot
                  }).count == 1,
                  ((openingRole == .findingObserved && opened.issueID == issue.id)
                    || openingRole == .originalResolvedDifferentFinding),
                  issue.updatedAt >= issue.createdAt,
                  IssueStatus(rawValue: issue.status) != nil,
                  try validCurrentIssueState(
                      issue,
                      workflow: workflow,
                      profile: lifecycle
                  ) else {
                throw invalid()
            }
        }
        guard unique(records.issues.map(\.openedByRecordID)),
              records.assets.allSatisfy({ asset in
            records.issues.filter {
                $0.assetID == asset.id
                    && $0.status != IssueStatus.resolved.rawValue
            }.count <= 1
        }) else {
            throw invalid()
        }
        for packet in records.packets {
            let ownedRecords = records.workflowRecords.filter { $0.packetID == packet.id }
            let ownedReports = records.reports.filter { $0.packetID == packet.id }
            if let currentID = packet.currentRecordID {
                let replacedIDs = Set(ownedReports.compactMap(\.replacesReportID))
                let reportTips = ownedReports.filter { !replacedIDs.contains($0.id) }
                let reportSourceIDs = ownedReports.map(\.sourceRecordID)
                guard packet.contentDeletedAt == nil,
                      packet.evaluationCounted,
                      let current = workflow[currentID], current.packetID == packet.id,
                      ownedRecords.allSatisfy({ $0.assetID == current.assetID }),
                      ownedReports.allSatisfy({ workflow[$0.sourceRecordID]?.assetID == current.assetID }),
                      unique(reportSourceIDs),
                      Set(reportSourceIDs) == Set(ownedRecords.map(\.id)),
                      reportTips.count == 1,
                      reportTips[0].sourceRecordID == currentID,
                      ownedReports.filter({ replacedIDs.contains($0.id) }).allSatisfy({
                          $0.pdfState == ReportPDFState.ready.rawValue
                      }) else {
                    throw invalid()
                }
                var visited = Set<UUID>()
                var chainReport: V4BackupReportDTO? = reportTips[0]
                while let value = chainReport {
                    guard visited.insert(value.id).inserted,
                          let source = workflow[value.sourceRecordID] else {
                        throw invalid()
                    }
                    if let priorID = value.replacesReportID {
                        guard let prior = reports[priorID],
                              prior.packetID == packet.id,
                              let priorSource = workflow[prior.sourceRecordID],
                              source.revisionKind
                                == WorkflowRevisionKind.clericalCorrection.rawValue,
                              source.revisesRecordID == priorSource.id,
                              source.recordRevisionRootID
                                == priorSource.recordRevisionRootID else {
                            throw invalid()
                        }
                        chainReport = prior
                    } else {
                        guard source.revisionKind
                                == WorkflowRevisionKind.original.rawValue,
                              source.revisesRecordID == nil,
                              source.completedAt == packet.createdAt else {
                            throw invalid()
                        }
                        chainReport = nil
                    }
                }
                guard visited.count == ownedReports.count else { throw invalid() }
            } else {
                guard packet.evaluationCounted,
                      let contentDeletedAt = packet.contentDeletedAt,
                      packet.createdAt <= contentDeletedAt,
                      ownedRecords.isEmpty, ownedReports.isEmpty else { throw invalid() }
            }
        }
        for report in records.reports {
            guard let packet = packets[report.packetID],
                  let source = workflow[report.sourceRecordID],
                  source.packetID == packet.id,
                  source.state == WorkflowState.completed.rawValue,
                  let sourceCompletedAt = source.completedAt,
                  report.createdAt >= sourceCompletedAt,
                  ReportPDFState(rawValue: report.pdfState) != nil,
                  (report.snapshotSchemaVersion == 1
                    || report.snapshotSchemaVersion == 2),
                  report.snapshotRelativePath == "snapshots/\(uuid(report.id)).json",
                  lowercaseHash(report.snapshotSHA256) else { throw invalid() }
            if let replacedID = report.replacesReportID {
                guard let replaced = reports[replacedID],
                      replaced.packetID == report.packetID,
                      replaced.createdAt < report.createdAt else { throw invalid() }
            }
        }
        try requireAcyclic(records.reports, id: \.id, next: \.replacesReportID)
        guard unique(records.reports.compactMap(\.replacesReportID)) else { throw invalid() }

        let counted = records.packets.filter(\.evaluationCounted)
            .map(\.stableRootID).sorted { uuid($0) < uuid($1) }
        let expectedPacks = Set(
            try records.assets.map { try releaseIdentity(for: $0) }
                + records.workflowRecords.map { try releaseIdentity(for: $0) }
        ).sorted().map {
            V4BackupPackV1(
                contentVersion: $0.contentVersion,
                packID: $0.packageID,
                schemaVersion: $0.schemaVersion
            )
        }
        guard unique(records.packets.map(\.stableRootID)),
              counted == manifest.consumedEvaluationRootIDs,
              manifest.packs == expectedPacks else { throw invalid() }
    }

    func validateObservationAndTime(_ records: V4BackupRecordsV1) throws {
        if records.recordsSchemaVersion < 4 {
            guard records.workflowRecords.allSatisfy({
                $0.observationBasisV1Data == nil && $0.temporalContextV1Data == nil
            }) else { throw invalid() }
            return
        }
        guard (4...6).contains(records.recordsSchemaVersion) else { throw invalid() }
        for record in records.workflowRecords {
            guard let basisData = record.observationBasisV1Data,
                  let temporalData = record.temporalContextV1Data else {
                throw invalid()
            }
            do {
                let basis = try ObservationAndTimeCodecV1.decodeObservationBasis(
                    basisData
                )
                let temporal = try ObservationAndTimeCodecV1.decodeTemporalContext(
                    temporalData
                )
                guard try ObservationAndTimeCodecV1.encode(basis) == basisData,
                      try ObservationAndTimeCodecV1.encode(temporal) == temporalData,
                      temporal.occurredAtUTC == record.observedAtUTC,
                      temporal.localDate == record.localDate,
                      temporal.localTime == record.localTime,
                      temporal.ianaTimeZoneIdentifier == record.timeZoneID else {
                    throw invalid()
                }
                let projectedOffset: Int?
                if let minutes = record.utcOffsetMinutes {
                    let (seconds, overflow) = minutes.multipliedReportingOverflow(
                        by: 60
                    )
                    guard !overflow else { throw invalid() }
                    projectedOffset = seconds
                } else {
                    projectedOffset = nil
                }
                guard temporal.utcOffsetSeconds == projectedOffset else {
                    throw invalid()
                }
            } catch {
                throw invalid()
            }
        }
    }

    func validateLocationRecords(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        let groups = [
            records.assetCompositionEdges, records.assetCompositionEvents,
            records.assetPlacementEvents, records.locationHierarchyEvents,
            records.locationMigrationReceipts, records.locationNodes,
        ]
        guard records.recordsSchemaVersion >= 5 else {
            guard groups.allSatisfy(\.isEmpty) else { throw invalid() }
            return
        }
        guard manifest.backupSchemaVersion == 4,
              ((records.recordsSchemaVersion == 5
                    && manifest.source.persistentSchemaVersion == 6)
                || (records.recordsSchemaVersion == 6
                    && manifest.source.persistentSchemaVersion == 7)),
              let sourceWorkspaceID = manifest.source.workspaceID else {
            throw invalid()
        }
        let workspaceID = WorkspaceID(rawValue: sourceWorkspaceID)
        func canonical<T: Codable>(_ type: T.Type, _ record: V5BackupLocationRecordV1) throws -> T {
            do { return try LocationPersistenceCodecV1.decode(type, from: record.canonicalData) }
            catch { throw invalid() }
        }
        do {
            let nodes: [LocationNodeV1] = try records.locationNodes.map {
                let value = try canonical(LocationNodeV1.self, $0)
                guard value.id == $0.id, value.workspaceID == workspaceID,
                      $0.secondaryCanonicalData == nil else { throw invalid() }
                return value
            }
            try LocationHierarchyPolicyV1.validate(nodes)
            let siteIDs = Set(records.sites.map(\.id))
            let assetIDs = Set(records.assets.map(\.id))
            let deletionEntries = records.deletionLedger?.entries ?? []
            let deletedSiteIDs = Set(deletionEntries.compactMap {
                $0.identity.kind == .site ? $0.identity.id : nil
            })
            let deletedAssetIDs = Set(deletionEntries.compactMap {
                $0.identity.kind == .asset ? $0.identity.id : nil
            })
            let knownSiteIDs = siteIDs.union(deletedSiteIDs)
            let knownAssetIDs = assetIDs.union(deletedAssetIDs)
            guard nodes.allSatisfy({
                knownSiteIDs.contains($0.siteID)
                    && (!deletedSiteIDs.contains($0.siteID) || $0.state == .archived)
            }) else { throw invalid() }
            let nodeIDs = Set(nodes.map(\.id))

            let placements: [AssetPlacementEventV1] = try records.assetPlacementEvents.map {
                let value = try canonical(AssetPlacementEventV1.self, $0)
                guard value.id == $0.id, value.workspaceID == workspaceID,
                      knownSiteIDs.contains(value.siteID), knownAssetIDs.contains(value.assetID),
                      value.locationNodeID.map(nodeIDs.contains) ?? true,
                      $0.secondaryCanonicalData == nil else { throw invalid() }
                return value
            }
            let placementIDs = Set(placements.map(\.id))
            guard placements.allSatisfy({ $0.predecessorEventID == nil || placementIDs.contains($0.predecessorEventID!) }),
                  assetIDs.isSubset(of: Set(placements.map(\.assetID))) else { throw invalid() }
            for history in Dictionary(grouping: placements, by: \.assetID).values {
                try AssetPlacementHistoryV1.validate(history)
            }
            let predecessorIDs = Set(placements.compactMap(\.predecessorEventID))
            let currentPlacements = placements.filter { !predecessorIDs.contains($0.id) }
            guard currentPlacements.count == Set(placements.map(\.assetID)).count,
                  Set(currentPlacements.map(\.assetID)).count == currentPlacements.count else {
                throw invalid()
            }
            let placementByID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
            var reachedPlacementIDs = Set<UUID>()
            for tip in currentPlacements {
                var cursor: AssetPlacementEventV1? = tip
                var visited = Set<UUID>()
                while let value = cursor {
                    guard value.assetID == tip.assetID,
                          visited.insert(value.id).inserted,
                          reachedPlacementIDs.insert(value.id).inserted else { throw invalid() }
                    cursor = value.predecessorEventID.flatMap { placementByID[$0] }
                }
            }
            guard reachedPlacementIDs.count == placements.count else { throw invalid() }
            let placementByAssetID = Dictionary(uniqueKeysWithValues: currentPlacements.map { ($0.assetID, $0) })
            let siteByAssetID = Dictionary(uniqueKeysWithValues: records.assets.map { ($0.id, $0.siteID) })
            guard currentPlacements.allSatisfy({ value in
                guard assetIDs.contains(value.assetID) else {
                    return deletedAssetIDs.contains(value.assetID)
                }
                return siteIDs.contains(value.siteID) && siteByAssetID[value.assetID] == value.siteID
            }) else { throw invalid() }

            let edges: [AssetCompositionEdgeV1] = try records.assetCompositionEdges.map {
                let value = try canonical(AssetCompositionEdgeV1.self, $0)
                guard value.id == $0.id, value.workspaceID == workspaceID,
                      knownAssetIDs.contains(value.parentAssetID),
                      knownAssetIDs.contains(value.childAssetID),
                      (!value.isActive || (assetIDs.contains(value.parentAssetID)
                        && assetIDs.contains(value.childAssetID))),
                      $0.secondaryCanonicalData == nil else { throw invalid() }
                return value
            }
            try AssetCompositionPolicyV1.validate(
                edges: edges.filter(\.isActive),
                placementByAssetID: placementByAssetID
            )
            let edgeIDs = Set(edges.map(\.id))
            let compositionEvents = try records.assetCompositionEvents.map {
                let value = try canonical(AssetCompositionEventV1.self, $0)
                guard value.id == $0.id, value.workspaceID == workspaceID,
                      edgeIDs.contains(value.edge.id),
                      knownAssetIDs.contains(value.edge.parentAssetID),
                      knownAssetIDs.contains(value.edge.childAssetID),
                      $0.secondaryCanonicalData == nil else { throw invalid() }
                return value
            }
            let compositionHistoryByEdgeID = Dictionary(grouping: compositionEvents, by: { $0.edge.id })
            guard Set(compositionHistoryByEdgeID.keys) == edgeIDs else { throw invalid() }
            let currentEdgeByID = Dictionary(uniqueKeysWithValues: edges.map { ($0.id, $0) })
            for (edgeID, history) in compositionHistoryByEdgeID {
                guard let currentEdge = currentEdgeByID[edgeID] else { throw invalid() }
                try AssetCompositionHistoryV1.validate(history, currentEdge: currentEdge)
            }
            for record in records.locationHierarchyEvents {
                guard let receiptData = record.secondaryCanonicalData else { throw invalid() }
                let plan = try canonical(LocationHierarchyChangePlanV1.self, record)
                let receipt = try LocationPersistenceCodecV1.decode(LocationHierarchyChangeReceiptV1.self, from: receiptData)
                guard plan.operationID == record.id, plan.workspaceID == workspaceID,
                      receipt.planSHA256 == plan.planSHA256,
                      receipt.mutationReceiptIdentity.workspaceID == workspaceID,
                      plan.affectedAssetIDs.allSatisfy(knownAssetIDs.contains),
                      (plan.beforeNodes + plan.afterNodes).allSatisfy({
                        $0.workspaceID == workspaceID && knownSiteIDs.contains($0.siteID)
                      }),
                      (plan.beforePaths + plan.afterPaths).allSatisfy({
                        knownSiteIDs.contains($0.siteID)
                      }) else { throw invalid() }
            }
            let migrationReceipts = try records.locationMigrationReceipts.map {
                let value = try canonical(LocationMigrationReceiptV1.self, $0)
                guard value.candidateGenerationID == $0.id, value.workspaceID == workspaceID,
                      value.candidateGenerationID == manifest.source.sourceGenerationID,
                      value.bindings.allSatisfy({
                        knownAssetIDs.contains($0.assetID)
                            && knownSiteIDs.contains($0.siteID)
                      }),
                      $0.secondaryCanonicalData == nil else { throw invalid() }
                return value
            }
            guard migrationReceipts.count <= 1 else { throw invalid() }
            try LocationMigrationIntegrityV1.validate(
                receipt: migrationReceipts.first,
                placementEvents: placements,
                knownAssetIDs: knownAssetIDs,
                liveAssetSiteByID: siteByAssetID
            )
        } catch {
            throw invalid()
        }
    }

    func validateDeletionLedger(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion == manifest.source.recordsSchemaVersion else {
            throw invalid()
        }
        let ledger: DeletionLedgerV2
        switch (
            records.recordsSchemaVersion,
            records.deletionLedger,
            records.mutationHistory
        ) {
        case (1, nil, nil):
            return
        case (2, let value?, nil):
            ledger = value
        case (3, let value?, let history?), (4, let value?, let history?),
             (5, let value?, let history?), (6, let value?, let history?):
            ledger = value
            do { try MutationJournalStoreV1.validateImportedSnapshot(history) }
            catch { throw invalid() }
            guard history.receipts.count
                    <= MutationJournalStoreV1.maximumReceiptValidationCount,
                  history.quarantines.count
                    <= MutationJournalStoreV1.maximumReceiptValidationCount,
                  history.entityRevisions.count
                    <= MutationReceiptV1.maximumPostImageCount else {
                throw invalid()
            }
        default:
            throw invalid()
        }
        do { try ledger.validate() }
        catch { throw invalid() }
        guard ledger.entries.count <= DeletionLedgerV2.maximumEntryCount else {
            throw invalid()
        }
        let byIdentity = Dictionary(
            uniqueKeysWithValues: ledger.entries.map { ($0.identity, $0) }
        )
        func deleted(_ kind: DeletionRecordKindV2, _ id: UUID) throws -> Bool {
            byIdentity[try DeletionIdentityV2(kind: kind, id: id)] != nil
        }
        guard try records.sites.allSatisfy({ try !deleted(.site, $0.id) }),
              try records.assets.allSatisfy({ try !deleted(.asset, $0.id) }),
              try records.workflowRecords.allSatisfy({
                  try !deleted(.workflowRecord, $0.id)
              }),
              try records.evidenceFiles.allSatisfy({
                  try !deleted(.evidenceFile, $0.id)
              }),
              try records.issues.allSatisfy({ try !deleted(.issue, $0.id) }),
              try records.reports.allSatisfy({ try !deleted(.report, $0.id) }) else {
            throw invalid()
        }
        for packet in records.packets {
            let identity = try DeletionIdentityV2(kind: .packet, id: packet.id)
            if packet.currentRecordID == nil {
                guard packet.evaluationCounted,
                      let deletedAt = packet.contentDeletedAt,
                      byIdentity[identity]?.deletedAt == deletedAt else {
                    throw invalid()
                }
            } else if byIdentity[identity] != nil {
                throw invalid()
            }
        }
    }

    func validCurrentIssueState(
        _ issue: V4BackupIssueDTO,
        workflow: [UUID: V4BackupWorkflowRecordDTO],
        profile: WorkspacePackageLifecycleProfileV1
    ) throws -> Bool {
        guard let opening = workflow[issue.openedByRecordID],
              opening.revisionKind == WorkflowRevisionKind.original.rawValue,
              opening.state == WorkflowState.completed.rawValue,
              let openingCompletedAt = opening.completedAt,
              openingCompletedAt == issue.createdAt else {
            return false
        }
        let openingOutcome = try outcomeProfile(
            opening.outcomeKey,
            in: profile.stage(opening.stage)
        )
        let ordinaryOpening = opening.stage == WorkflowStage.check.rawValue
            && openingOutcome.role == .findingObserved
            && opening.issueID == issue.id
        let differentIssueOpening = opening.stage == WorkflowStage.recheck.rawValue
            && openingOutcome.role == .originalResolvedDifferentFinding
            && opening.issueID != issue.id
        guard ordinaryOpening || differentIssueOpening else { return false }

        let relevant = workflow.values.filter {
            $0.revisionKind == WorkflowRevisionKind.original.rawValue
                && ($0.id == opening.id || $0.issueID == issue.id)
        }
        let substantive = relevant.filter {
            $0.state == WorkflowState.completed.rawValue
        }
        let drafts = relevant.filter { $0.state == WorkflowState.draft.rawValue }
        guard drafts.count <= 1 else { return false }
        var chain = [opening]
        var visited: Set<UUID> = [opening.id]
        var current = opening
        while true {
            let children = substantive.filter { $0.parentRecordID == current.id }
            guard children.count <= 1 else { return false }
            guard let child = children.first else { break }
            guard visited.insert(child.id).inserted,
                  child.assetID == issue.assetID,
                  child.issueID == issue.id,
                  child.state == WorkflowState.completed.rawValue,
                  let parentCompletedAt = current.completedAt,
                  child.startedAt >= parentCompletedAt,
                  child.completedAt.map({ $0 >= parentCompletedAt }) == true else {
                return false
            }
            chain.append(child)
            current = child
        }
        guard visited.count == substantive.count else { return false }

        var expectedStatus = IssueStatus.open.rawValue
        var expectedResolvedByRecordID: UUID?
        var expectedUpdatedAt = openingCompletedAt
        for record in chain.dropFirst() {
            guard let completedAt = record.completedAt else { return false }
            switch WorkflowStage(rawValue: record.stage) {
            case .work:
                guard expectedStatus == IssueStatus.open.rawValue else {
                    return false
                }
                expectedStatus = IssueStatus.recheckDue.rawValue
                expectedResolvedByRecordID = nil
                expectedUpdatedAt = completedAt
            case .recheck:
                guard expectedStatus == IssueStatus.recheckDue.rawValue else {
                    return false
                }
                let role = try outcomeProfile(
                    record.outcomeKey,
                    in: profile.stage(record.stage)
                ).role
                switch role {
                case .resolved, .originalResolvedDifferentFinding:
                    expectedStatus = IssueStatus.resolved.rawValue
                    expectedResolvedByRecordID = record.id
                    expectedUpdatedAt = completedAt
                case .findingStillPresent:
                    expectedStatus = IssueStatus.open.rawValue
                    expectedResolvedByRecordID = nil
                    expectedUpdatedAt = completedAt
                case .couldNotVerify:
                    break
                default:
                    return false
                }
            case .check, nil:
                return false
            }
        }
        if let draft = drafts.first {
            guard draft.assetID == issue.assetID,
                  draft.issueID == issue.id,
                  draft.parentRecordID == chain.last?.id else {
                return false
            }
            switch WorkflowStage(rawValue: draft.stage) {
            case .work:
                guard expectedStatus == IssueStatus.open.rawValue else {
                    return false
                }
            case .recheck:
                guard expectedStatus == IssueStatus.recheckDue.rawValue else {
                    return false
                }
            case .check, nil:
                return false
            }
        }
        return issue.status == expectedStatus
            && issue.resolvedByRecordID == expectedResolvedByRecordID
            && issue.updatedAt == expectedUpdatedAt
    }

    func validateOwnedMembers(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1,
        cancellation: StreamingArchiveCancellationV1
    ) throws {
        var expected = Set(["manifest.json", "records.json"])
        let normalizer = MediaNormalizerV1()
        for evidence in records.evidenceFiles {
            try cancellation.checkpoint()
            let id = uuid(evidence.id)
            let originalPath = "media/\(id).jpg"
            let thumbnailPath = "thumbnails/\(id).jpg"
            do {
                guard let original = members[originalPath],
                      original.count == evidence.byteCount,
                      CanonicalJSONV1.sha256(original) == evidence.sha256 else {
                    throw invalid()
                }
                _ = try normalizer.validateCanonicalJPEG(original, kind: .original)
            }
            do {
                guard let thumbnail = members[thumbnailPath],
                      thumbnail.count == evidence.thumbnailByteCount,
                      CanonicalJSONV1.sha256(thumbnail) == evidence.thumbnailSHA256 else {
                    throw invalid()
                }
                _ = try normalizer.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            }
            expected.insert(originalPath)
            expected.insert(thumbnailPath)
        }
        for report in records.reports {
            try cancellation.checkpoint()
            let id = uuid(report.id)
            expected.insert("snapshots/\(id).json")
            switch ReportPDFState(rawValue: report.pdfState) {
            case .ready:
                let path = "pdfs/\(id).pdf"
                guard report.pdfRelativePath == path,
                      let hash = report.pdfSHA256,
                      lowercaseHash(hash),
                      let bytes = members[path],
                      CanonicalJSONV1.sha256(bytes) == hash,
                      let document = PDFDocument(data: bytes),
                      document.pageCount > 0 else { throw invalid() }
                expected.insert(path)
            case .pending, .failed:
                guard report.pdfRelativePath == nil, report.pdfSHA256 == nil else { throw invalid() }
            case nil:
                throw invalid()
            }
        }
        guard members.keys == expected,
              Set(manifest.entries.map(\.path)) == expected.subtracting(["manifest.json"]) else {
            throw invalid()
        }
    }
}

private extension BackupPackageValidatorV1 {
    func validDraftSemantics(
        _ record: V4BackupWorkflowRecordDTO,
        profile: WorkspacePackageLifecycleProfileV1,
        workflow: [UUID: V4BackupWorkflowRecordDTO],
        issues: [UUID: V4BackupIssueDTO]
    ) -> Bool {
        let hasNoAcknowledgements = acknowledgementPresence(record).allSatisfy { !$0 }
        let hasNoTime = timeFields(record).allSatisfy { !$0 }
        let captureStep = record.draftStepKey.flatMap {
            WorkflowDraftStep(rawValue: $0)
        }
        let validCaptureStep = captureStep == .wide
            || captureStep == .close
            || captureStep == .outcome
        guard record.couldNotVerifyKey == nil,
              record.couldNotVerifyDisplaySnapshot == nil,
              record.couldNotVerifyRegistryVersion == nil,
              record.workPerformedLocalDate == nil,
              record.workDescription == nil,
              record.note == nil else { return false }
        switch WorkflowStage(rawValue: record.stage) {
        case .check:
            return record.parentRecordID == nil && record.issueID == nil
                && validCaptureStep
                && validFrozenTimeAndAcknowledgements(record, profile: profile)
        case .recheck:
            return record.parentRecordID != nil && record.issueID != nil
                && validCaptureStep
                && validFrozenTimeAndAcknowledgements(record, profile: profile)
                && validDraftParentAuthority(
                    record,
                    workflow: workflow,
                    issues: issues
                )
        case .work:
            return record.parentRecordID != nil && record.issueID != nil
                && record.draftStepKey == nil
                && hasNoAcknowledgements && hasNoTime
                && profile.stages.contains(where: {
                    $0.stageKey == WorkflowStage.work.rawValue
                })
                && validDraftParentAuthority(
                    record,
                    workflow: workflow,
                    issues: issues
                )
        case nil:
            return false
        }
    }

    func validDraftParentAuthority(
        _ record: V4BackupWorkflowRecordDTO,
        workflow: [UUID: V4BackupWorkflowRecordDTO],
        issues: [UUID: V4BackupIssueDTO]
    ) -> Bool {
        guard let parentID = record.parentRecordID,
              let issueID = record.issueID,
              let parent = workflow[parentID],
              let issue = issues[issueID],
              parent.assetID == record.assetID,
              issue.assetID == record.assetID,
              parent.revisionKind == WorkflowRevisionKind.original.rawValue,
              parent.state == WorkflowState.completed.rawValue,
              let parentCompletedAt = parent.completedAt,
              parent.finalizationMutationID != nil,
              parent.packID == record.packID,
              parent.packSchemaVersion == record.packSchemaVersion,
              parent.packContentVersion == record.packContentVersion,
              parent.issueID == issue.id || issue.openedByRecordID == parent.id,
              record.startedAt >= parentCompletedAt,
              record.startedAt >= issue.updatedAt else {
            return false
        }
        return true
    }

    func validFrozenTimeAndAcknowledgements(
        _ record: V4BackupWorkflowRecordDTO,
        profile: WorkspacePackageLifecycleProfileV1
    ) -> Bool {
        let acknowledgements = profile.requiredAcknowledgementKeys.compactMap { key in
            profile.package.acknowledgements.first(where: { $0.key == key })
        }
        let stored = [
            (
                record.afterDarkAcknowledgementKey,
                record.afterDarkAcknowledgementCopy,
                record.afterDarkAcknowledgementVersion,
                record.afterDarkAcknowledgementAccepted
            ),
            (
                record.safePositionAcknowledgementKey,
                record.safePositionAcknowledgementCopy,
                record.safePositionAcknowledgementVersion,
                record.safePositionAcknowledgementAccepted
            ),
        ]
        guard acknowledgements.count == profile.requiredAcknowledgementKeys.count,
              stored.filter({ $0.0 != nil }).count == acknowledgements.count,
              stored.filter({ $0.0 == nil }).allSatisfy({
                  $0.1 == nil && $0.2 == nil && $0.3 == nil
              }),
              let observedAtUTC = record.observedAtUTC,
              let timeZoneID = record.timeZoneID,
              observedAtUTC == record.startedAt,
              let frozen = try? TimeContextRule.freeze(
                  observedAtUTC: observedAtUTC,
                  confirmedTimeZoneID: timeZoneID
              ),
              frozen.utcOffsetMinutes == record.utcOffsetMinutes,
              frozen.localDate == record.localDate,
              frozen.localTime == record.localTime,
              acknowledgements.allSatisfy({ expected in
                  stored.filter({ row in
                      row.0 == expected.key && row.1 == expected.copy
                        && row.2 == expected.version && row.3 == true
                  }).count == 1
              }) else {
            return false
        }
        return true
    }

    func validCorrection(
        _ record: V4BackupWorkflowRecordDTO,
        prior: V4BackupWorkflowRecordDTO,
        root: V4BackupWorkflowRecordDTO
    ) -> Bool {
        record.schemaVersion == prior.schemaVersion
            && record.assetID == prior.assetID
            && record.packetID == prior.packetID
            && record.issueID == prior.issueID
            && record.parentRecordID == prior.parentRecordID
            && record.recordRevisionRootID == prior.recordRevisionRootID
            && prior.recordRevisionRootID == root.id
            && record.stage == prior.stage
            && record.state == prior.state
            && record.draftStepKey == prior.draftStepKey
            && record.startedAt == prior.startedAt
            && record.completedAt == prior.completedAt
            && record.observedAtUTC == prior.observedAtUTC
            && record.timeZoneID == prior.timeZoneID
            && record.utcOffsetMinutes == prior.utcOffsetMinutes
            && record.localDate == prior.localDate
            && record.localTime == prior.localTime
            && record.afterDarkAcknowledgementKey
                == prior.afterDarkAcknowledgementKey
            && record.afterDarkAcknowledgementCopy
                == prior.afterDarkAcknowledgementCopy
            && record.afterDarkAcknowledgementVersion
                == prior.afterDarkAcknowledgementVersion
            && record.afterDarkAcknowledgementAccepted
                == prior.afterDarkAcknowledgementAccepted
            && record.safePositionAcknowledgementKey
                == prior.safePositionAcknowledgementKey
            && record.safePositionAcknowledgementCopy
                == prior.safePositionAcknowledgementCopy
            && record.safePositionAcknowledgementVersion
                == prior.safePositionAcknowledgementVersion
            && record.safePositionAcknowledgementAccepted
                == prior.safePositionAcknowledgementAccepted
            && record.packID == prior.packID
            && record.packSchemaVersion == prior.packSchemaVersion
            && record.packContentVersion == prior.packContentVersion
            && record.pdfTemplateID == prior.pdfTemplateID
            && record.pdfTemplateVersion == prior.pdfTemplateVersion
            && record.outcomeKey == prior.outcomeKey
            && record.couldNotVerifyKey == prior.couldNotVerifyKey
            && record.couldNotVerifyDisplaySnapshot
                == prior.couldNotVerifyDisplaySnapshot
            && record.couldNotVerifyRegistryVersion
                == prior.couldNotVerifyRegistryVersion
            && record.workPerformedLocalDate == prior.workPerformedLocalDate
            && record.workDescription == prior.workDescription
            && record.note != prior.note
    }

    func validDraftEvidence(
        _ record: V4BackupWorkflowRecordDTO,
        profile: WorkspacePackageLifecycleProfileV1,
        owned: [V4BackupEvidenceFileDTO]
    ) -> Bool {
        switch WorkflowStage(rawValue: record.stage) {
        case .work:
            return profile.stages.contains(where: {
                $0.stageKey == WorkflowStage.work.rawValue
            }) && record.draftStepKey == nil && owned.isEmpty
        case .check, .recheck:
            guard let step = record.draftStepKey.flatMap({
                WorkflowDraftStep(rawValue: $0)
            }) else { return false }
            let purposes = Set(owned.map(\.purposeKey))
            let orderedRequired = profile.evidencePurposeKeys(for: .captureRequired)
            let allowed = Set(
                orderedRequired
                    + profile.evidencePurposeKeys(for: .captureSupplementary)
            )
            guard purposes.count == owned.count,
                  purposes.isSubset(of: allowed) else {
                return false
            }
            switch step {
            case .wide:
                return owned.isEmpty
            case .close:
                return orderedRequired.first.map { purposes == [$0] }
                    ?? owned.isEmpty
            case .outcome:
                guard orderedRequired.count > 1 else { return true }
                return !purposes.contains(orderedRequired[1])
                    || purposes.contains(orderedRequired[0])
            case .review:
                return false
            }
        case nil:
            return false
        }
    }

    func validCompletedSemantics(
        _ record: V4BackupWorkflowRecordDTO,
        profile: WorkspacePackageLifecycleProfileV1
    ) -> Bool {
        let hasNoAcknowledgements = acknowledgementPresence(record).allSatisfy { !$0 }
        let hasNoTime = timeFields(record).allSatisfy { !$0 }
        let hasAnyCNV = record.couldNotVerifyKey != nil
            || record.couldNotVerifyDisplaySnapshot != nil
            || record.couldNotVerifyRegistryVersion != nil
        let hasCompleteCNV = record.couldNotVerifyKey != nil
            && record.couldNotVerifyDisplaySnapshot != nil
            && record.couldNotVerifyRegistryVersion != nil
        let stageProfile = try? profile.stage(record.stage)
        let outcome = stageProfile.flatMap { stage in
            stage.outcomes.first(where: { $0.key == record.outcomeKey })
        }
        guard (outcome?.role == .couldNotVerify) == hasCompleteCNV,
              hasCompleteCNV || !hasAnyCNV,
              validOptionalTrimmed(record.note, maximum: 1_000) else { return false }
        if hasCompleteCNV {
            guard record.couldNotVerifyRegistryVersion == profile.package.couldNotVerifyReasons.version,
                  profile.package.couldNotVerifyReasons.entries.contains(where: {
                      $0.key == record.couldNotVerifyKey
                        && $0.display == record.couldNotVerifyDisplaySnapshot
                  }) else { return false }
        }
        switch WorkflowStage(rawValue: record.stage) {
        case .check:
            return record.parentRecordID == nil && record.packetID != nil
                && outcome != nil
                && ((outcome?.role == .findingObserved) == (record.issueID != nil))
                && record.workPerformedLocalDate == nil && record.workDescription == nil
                && validFrozenTimeAndAcknowledgements(record, profile: profile)
        case .recheck:
            return record.parentRecordID != nil && record.issueID != nil
                && record.packetID != nil
                && outcome != nil
                && record.workPerformedLocalDate == nil && record.workDescription == nil
                && validFrozenTimeAndAcknowledgements(record, profile: profile)
        case .work:
            let workOutcome = profile.stages.first(where: {
                $0.stageKey == record.stage
            })?.outcomes.first(where: { $0.key == record.outcomeKey })
            return record.parentRecordID != nil && record.issueID != nil
                && record.packetID == nil && workOutcome?.role == .workRecorded
                && record.workPerformedLocalDate.map(validLocalDate) == true
                && validRequiredTrimmed(record.workDescription, maximum: 160)
                && hasNoAcknowledgements && hasNoTime
        case nil:
            return false
        }
    }

    func acknowledgementPresence(_ value: V4BackupWorkflowRecordDTO) -> [Bool] {
        [
            value.afterDarkAcknowledgementKey != nil,
            value.afterDarkAcknowledgementCopy != nil,
            value.afterDarkAcknowledgementVersion != nil,
            value.afterDarkAcknowledgementAccepted != nil,
            value.safePositionAcknowledgementKey != nil,
            value.safePositionAcknowledgementCopy != nil,
            value.safePositionAcknowledgementVersion != nil,
            value.safePositionAcknowledgementAccepted != nil,
        ]
    }

    func timeFields(_ value: V4BackupWorkflowRecordDTO) -> [Bool] {
        [
            value.observedAtUTC != nil,
            value.timeZoneID != nil,
            value.utcOffsetMinutes != nil,
            value.localDate != nil,
            value.localTime != nil,
        ]
    }

    func validOptionalTrimmed(_ value: String?, maximum: Int) -> Bool {
        guard let value else { return true }
        return validRequiredTrimmed(value, maximum: maximum)
    }

    func validRequiredTrimmed(_ value: String?, maximum: Int) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == trimmed && !value.isEmpty && value.count <= maximum
    }

    func validLocalDate(_ value: String) -> Bool {
        guard value.range(
            of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
            options: .regularExpression
        ) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    func stageDisplay(
        _ value: String,
        profile: WorkspacePackageLifecycleProfileV1
    ) -> String? {
        (try? profile.stage(value))?.stageDisplay
    }

    func outcomeDisplay(
        _ value: String?,
        profile: WorkspacePackageLifecycleProfileV1
    ) -> String? {
        guard let value else { return nil }
        let matches = profile.stages.flatMap(\.outcomes).filter { $0.key == value }
        guard let display = matches.first?.display,
              matches.allSatisfy({ $0.display == display }) else { return nil }
        return display
    }

    func frozenCouldNotVerify(
        _ record: V4BackupWorkflowRecordDTO
    ) -> CouldNotVerifySnapshotV1? {
        guard let key = record.couldNotVerifyKey,
              let display = record.couldNotVerifyDisplaySnapshot,
              let version = record.couldNotVerifyRegistryVersion else {
            return nil
        }
        return CouldNotVerifySnapshotV1(
            display: display,
            key: key,
            registryVersion: version
        )
    }

    func validateReports(
        _ records: V4BackupRecordsV1,
        members: ValidatedV4BackupMembersV1,
        cancellation: StreamingArchiveCancellationV1
    ) throws {
        let workflow = Dictionary(uniqueKeysWithValues: records.workflowRecords.map { ($0.id, $0) })
        let packets = Dictionary(uniqueKeysWithValues: records.packets.map { ($0.id, $0) })
        let evidence = Dictionary(uniqueKeysWithValues: records.evidenceFiles.map { ($0.id, $0) })
        let issues = Dictionary(uniqueKeysWithValues: records.issues.map { ($0.id, $0) })
        let assets = Dictionary(uniqueKeysWithValues: records.assets.map { ($0.id, $0) })
        let sites = Dictionary(uniqueKeysWithValues: records.sites.map { ($0.id, $0) })
        for report in records.reports {
            try cancellation.checkpoint()
            guard let bytes = members["snapshots/\(uuid(report.id)).json"],
                  CanonicalJSONV1.sha256(bytes) == report.snapshotSHA256,
                  let source = workflow[report.sourceRecordID],
                  let packet = packets[report.packetID],
                  let asset = assets[source.assetID],
                  let site = sites[asset.siteID] else { throw invalid() }
            let lifecycle = try profile(for: source)
            let snapshot = try ReportSnapshotEncoderV1().decode(bytes)
            let effectiveSourceID = source.evidenceSourceRecordID ?? source.id
            guard snapshot.reportID == report.id,
                  snapshot.sourceRecordID == source.id,
                  snapshot.evidenceSourceRecordID == effectiveSourceID,
                  snapshot.packetID == packet.id,
                  snapshot.stableRootID == packet.stableRootID,
                  snapshot.snapshotSchemaVersion == report.snapshotSchemaVersion,
                  snapshot.snapshotCreatedAt == report.createdAt,
                  snapshot.stage == source.stage,
                  snapshot.outcome == source.outcomeKey,
                  snapshot.note == source.note,
                  snapshot.couldNotVerify == frozenCouldNotVerify(source),
                  snapshot.pack.id == lifecycle.release.packageID,
                  snapshot.pack.schemaVersion == lifecycle.release.schemaVersion,
                  snapshot.pack.contentVersion == lifecycle.release.contentVersion,
                  snapshot.pdfTemplate.id == source.pdfTemplateID,
                  snapshot.pdfTemplate.version == source.pdfTemplateVersion,
                  snapshot.asset.label == asset.label,
                  snapshot.site.label == site.label,
                  snapshot.site.address == site.address,
                  snapshot.disclaimer == lifecycle.package.disclaimer,
                  snapshot.display.assetSingular == lifecycle.package.nouns.asset.singular,
                  snapshot.display.checkSingular == lifecycle.package.nouns.check.singular,
                  snapshot.display.issueSingular == lifecycle.package.nouns.issue.singular,
                  snapshot.display.stage == stageDisplay(source.stage, profile: lifecycle),
                  snapshot.display.outcome == outcomeDisplay(source.outcomeKey, profile: lifecycle),
                  snapshot.timeContext.observedAtUTC == source.observedAtUTC,
                  snapshot.timeContext.timeZoneID == source.timeZoneID,
                  snapshot.timeContext.utcOffsetMinutes == source.utcOffsetMinutes,
                  snapshot.timeContext.localDate == source.localDate,
                  snapshot.timeContext.localTime == source.localTime else { throw invalid() }
            try validateAcknowledgements(snapshot, source: source, profile: lifecycle)

            guard let effective = workflow[effectiveSourceID],
                  let effectiveCompletedAt = effective.completedAt else {
                throw invalid()
            }
            let chain = try parentChain(endingAt: effective, workflow: workflow)
            let expectedIssues = try issueSnapshots(
                effectiveSourceID: effectiveSourceID,
                assetID: source.assetID,
                workflow: workflow,
                issues: issues,
                profile: lifecycle
            )
            let expectedHistory = expectedIssues.isEmpty
                ? []
                : Array(chain.dropLast()).sorted(by: recordChronology)
            guard expectedHistory.allSatisfy({ record in
                      record.completedAt.map { $0 < effectiveCompletedAt } == true
                  }),
                  snapshot.history.map(\.recordID) == expectedHistory.map(\.id),
                  !snapshot.history.contains(where: { $0.recordID == effective.id }),
                  snapshot.issues == expectedIssues else {
                throw invalid()
            }
            try validateSnapshotObservationAndTime(
                snapshot,
                source: source,
                expectedHistory: expectedHistory
            )

            var orderedEvidence = records.evidenceFiles.filter {
                $0.recordID == effectiveSourceID
            }.sorted { evidenceOrder($0, $1, profile: lifecycle) }
            var seenEvidenceIDs = Set(orderedEvidence.map(\.id))
            for (history, record) in zip(snapshot.history, expectedHistory) {
                let historyEvidence = records.evidenceFiles.filter {
                    $0.recordID == record.id
                }.sorted { evidenceOrder($0, $1, profile: lifecycle) }
                guard record.assetID == source.assetID,
                      record.state == WorkflowState.completed.rawValue,
                      record.completedAt == history.completedAt,
                      record.stage == history.stage,
                      record.outcomeKey == history.outcome,
                      history.couldNotVerify == frozenCouldNotVerify(record),
                      record.note == history.note,
                      record.workDescription == history.workDescription,
                      record.workPerformedLocalDate == history.workPerformedLocalDate,
                      history.stageDisplay == stageDisplay(record.stage, profile: lifecycle),
                      history.outcomeDisplay == outcomeDisplay(record.outcomeKey, profile: lifecycle),
                      history.evidenceIDs == historyEvidence.map(\.id),
                      history.issueIDs == (try historyIssueIDs(
                          record: record,
                          assetID: source.assetID,
                          issues: issues
                      )) else {
                    throw invalid()
                }
                for row in historyEvidence where seenEvidenceIDs.insert(row.id).inserted {
                    orderedEvidence.append(row)
                }
            }
            guard snapshot.evidence.map(\.evidenceID) == orderedEvidence.map(\.id) else {
                throw invalid()
            }
            for (value, row) in zip(snapshot.evidence, orderedEvidence) {
                guard evidence[value.evidenceID]?.id == row.id,
                      value.recordID == row.recordID,
                      value.purposeKey == row.purposeKey,
                      value.mimeType == row.mimeType,
                      value.byteCount == row.byteCount,
                      value.sha256 == row.sha256,
                      value.relativePath == row.relativePath,
                      value.thumbnailByteCount == row.thumbnailByteCount,
                      value.thumbnailSHA256 == row.thumbnailSHA256,
                      value.thumbnailRelativePath == row.thumbnailRelativePath,
                      value.createdAt == row.createdAt,
                      lifecycle.package.evidencePurposes.first(where: { $0.key == row.purposeKey })?.display
                        == value.purposeDisplay else { throw invalid() }
            }
        }
    }

    func validateSnapshotObservationAndTime(
        _ snapshot: ReportSnapshotV1,
        source: V4BackupWorkflowRecordDTO,
        expectedHistory: [V4BackupWorkflowRecordDTO]
    ) throws {
        switch snapshot.snapshotSchemaVersion {
        case 1:
            guard snapshot.observationBasis == nil,
                  snapshot.temporalContext == nil,
                  snapshot.history.allSatisfy({
                      $0.observationBasis == nil && $0.temporalContext == nil
                  }) else {
                throw invalid()
            }
        case 2:
            guard snapshot.history.count == expectedHistory.count else {
                throw invalid()
            }
            do {
                guard let sourceBasisData = source.observationBasisV1Data,
                      let sourceTemporalData = source.temporalContextV1Data,
                      snapshot.observationBasis
                        == (try ObservationAndTimeCodecV1.decodeObservationBasis(
                            sourceBasisData
                        )),
                      snapshot.temporalContext
                        == (try ObservationAndTimeCodecV1.decodeTemporalContext(
                            sourceTemporalData
                        )) else {
                    throw invalid()
                }
                for (history, record) in zip(snapshot.history, expectedHistory) {
                    guard let basisData = record.observationBasisV1Data,
                          let temporalData = record.temporalContextV1Data,
                          history.observationBasis
                            == (try ObservationAndTimeCodecV1.decodeObservationBasis(
                                basisData
                            )),
                          history.temporalContext
                            == (try ObservationAndTimeCodecV1.decodeTemporalContext(
                                temporalData
                            )) else {
                        throw invalid()
                    }
                }
            } catch {
                throw invalid()
            }
        default:
            throw invalid()
        }
    }

    func historyIssueIDs(
        record: V4BackupWorkflowRecordDTO,
        assetID: UUID,
        issues: [UUID: V4BackupIssueDTO]
    ) throws -> [UUID] {
        var result = Set(record.issueID.map { [$0] } ?? [])
        result.formUnion(issues.values.compactMap {
            $0.openedByRecordID == record.id ? $0.id : nil
        })
        guard result.allSatisfy({ issues[$0]?.assetID == assetID }) else {
            throw invalid()
        }
        return result.sorted { uuid($0) < uuid($1) }
    }

    func recordChronology(
        _ lhs: V4BackupWorkflowRecordDTO,
        _ rhs: V4BackupWorkflowRecordDTO
    ) -> Bool {
        guard let left = lhs.completedAt, let right = rhs.completedAt else {
            return false
        }
        return left < right || (left == right && uuid(lhs.id) < uuid(rhs.id))
    }

    func evidenceOrder(
        _ lhs: V4BackupEvidenceFileDTO,
        _ rhs: V4BackupEvidenceFileDTO,
        profile: WorkspacePackageLifecycleProfileV1
    ) -> Bool {
        let left = purposeOrder(lhs.purposeKey, profile: profile)
        let right = purposeOrder(rhs.purposeKey, profile: profile)
        return left == right ? uuid(lhs.id) < uuid(rhs.id) : left < right
    }

    func purposeOrder(
        _ value: String,
        profile: WorkspacePackageLifecycleProfileV1
    ) -> Int {
        profile.evidencePurposes.firstIndex(where: { $0.key == value })
            ?? profile.evidencePurposes.count
    }

    func issueSnapshots(
        effectiveSourceID: UUID,
        assetID: UUID,
        workflow: [UUID: V4BackupWorkflowRecordDTO],
        issues: [UUID: V4BackupIssueDTO],
        profile: WorkspacePackageLifecycleProfileV1
    ) throws -> [IssueSnapshotV1] {
        guard let effective = workflow[effectiveSourceID],
              effective.assetID == assetID,
              effective.revisionKind == WorkflowRevisionKind.original.rawValue else {
            throw invalid()
        }
        let chain = try parentChain(endingAt: effective, workflow: workflow)
        var issueIDs = Set(chain.compactMap(\.issueID))
        issueIDs.formUnion(issues.values.compactMap { issue in
            chain.contains(where: { $0.id == issue.openedByRecordID })
                ? issue.id
                : nil
        })

        var result: [IssueSnapshotV1] = []
        for issueID in issueIDs {
            guard let issue = issues[issueID],
                  issue.assetID == assetID,
                  let opening = chain.first(where: {
                      $0.id == issue.openedByRecordID
                  }),
                  issue.createdAt == opening.completedAt,
                  profile.package.issueLabels.filter({
                      $0.key == issue.labelKey
                        && $0.display == issue.labelDisplaySnapshot
                  }).count == 1 else {
                throw invalid()
            }
            var status = IssueStatus.open.rawValue
            var resolvedByRecordID: UUID?
            var updatedAt = issue.createdAt
            for record in chain where record.issueID == issue.id {
                guard let completedAt = record.completedAt else { throw invalid() }
                switch WorkflowStage(rawValue: record.stage) {
                case .work:
                    status = IssueStatus.recheckDue.rawValue
                    resolvedByRecordID = nil
                    updatedAt = completedAt
                case .recheck:
                    let role = try outcomeProfile(
                        record.outcomeKey,
                        in: profile.stage(record.stage)
                    ).role
                    switch role {
                    case .resolved, .originalResolvedDifferentFinding:
                        status = IssueStatus.resolved.rawValue
                        resolvedByRecordID = record.id
                        updatedAt = completedAt
                    case .findingStillPresent:
                        status = IssueStatus.open.rawValue
                        resolvedByRecordID = nil
                        updatedAt = completedAt
                    case .couldNotVerify:
                        break
                    default:
                        throw invalid()
                    }
                case .check:
                    guard record.id == issue.openedByRecordID else { throw invalid() }
                case nil:
                    throw invalid()
                }
            }
            result.append(IssueSnapshotV1(
                createdAt: issue.createdAt,
                display: issue.labelDisplaySnapshot,
                issueID: issue.id,
                key: issue.labelKey,
                openedByRecordID: issue.openedByRecordID,
                resolvedByRecordID: resolvedByRecordID,
                status: status,
                updatedAt: updatedAt
            ))
        }
        return result.sorted {
            $0.createdAt < $1.createdAt
                || ($0.createdAt == $1.createdAt
                    && uuid($0.issueID) < uuid($1.issueID))
        }
    }

    func parentChain(
        endingAt record: V4BackupWorkflowRecordDTO,
        workflow: [UUID: V4BackupWorkflowRecordDTO]
    ) throws -> [V4BackupWorkflowRecordDTO] {
        var reversed: [V4BackupWorkflowRecordDTO] = []
        var current: V4BackupWorkflowRecordDTO? = record
        var seen = Set<UUID>()
        while let value = current {
            guard seen.insert(value.id).inserted,
                  value.assetID == record.assetID,
                  value.revisionKind == WorkflowRevisionKind.original.rawValue else {
                throw invalid()
            }
            reversed.append(value)
            if let parentID = value.parentRecordID {
                guard let parent = workflow[parentID] else { throw invalid() }
                current = parent
            } else {
                current = nil
            }
        }
        return reversed.reversed()
    }

    func validateAcknowledgements(
        _ snapshot: ReportSnapshotV1,
        source: V4BackupWorkflowRecordDTO,
        profile: WorkspacePackageLifecycleProfileV1
    ) throws {
        let acknowledgements = profile.requiredAcknowledgementKeys.compactMap { key in
            profile.package.acknowledgements.first(where: { $0.key == key })
        }
        guard acknowledgements.count == profile.requiredAcknowledgementKeys.count,
              snapshot.acknowledgements.count == acknowledgements.count else {
            throw invalid()
        }
        let stored = [
            (
                source.afterDarkAcknowledgementKey,
                source.afterDarkAcknowledgementCopy,
                source.afterDarkAcknowledgementVersion,
                source.afterDarkAcknowledgementAccepted
            ),
            (
                source.safePositionAcknowledgementKey,
                source.safePositionAcknowledgementCopy,
                source.safePositionAcknowledgementVersion,
                source.safePositionAcknowledgementAccepted
            ),
        ]
        for index in snapshot.acknowledgements.indices {
            let value = snapshot.acknowledgements[index]
            let expected = acknowledgements[index]
            guard let row = stored.first(where: { $0.0 == expected.key }) else {
                throw invalid()
            }
            guard value.key == expected.key, value.copy == expected.copy,
                  value.version == expected.version, value.accepted,
                  row.0 == value.key, row.1 == value.copy,
                  row.2 == value.version, row.3 == value.accepted else { throw invalid() }
        }
    }

    func requireAcyclic<T>(
        _ values: [T],
        id: KeyPath<T, UUID>,
        next: KeyPath<T, UUID?>
    ) throws {
        let byID = Dictionary(uniqueKeysWithValues: values.map { ($0[keyPath: id], $0) })
        for value in values {
            var seen = Set<UUID>()
            var cursor: UUID? = value[keyPath: id]
            while let current = cursor {
                guard seen.insert(current).inserted, let row = byID[current] else { throw invalid() }
                cursor = row[keyPath: next]
            }
        }
    }

    func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
    func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }
    func lowercaseHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
    func invalid() -> BackupPackageValidationErrorV1 { .invalidPackage }
}

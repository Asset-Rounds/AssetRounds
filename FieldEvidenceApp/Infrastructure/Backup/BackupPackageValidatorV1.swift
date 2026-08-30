import Darwin
import Foundation

enum C34SceneNavigationPackageValidationBoundaryV1 {
    static func validate() throws {
        guard C34SceneNavigationDeviceLifecycleBoundaryV1.validate() else {
            throw SceneNavigationFailureV1.invalidSnapshot
        }
    }
}

enum C50IncumbentFileExchangePackageValidationBoundaryV1 {
    static let allowedAdapterMemberCount = 0
    static let rejectsSourceBytes = true
    static let rejectsQuarantineBytes = true
    static let rejectsBookmarksAndExternalPaths = true
    static let validatesCanonicalImportedRowsWithExistingOwners = true
}

private struct PrivacyTransformManifestDecodeEnvelopeV1: Decodable {
    let policyID: UUID
    let policyRevision: UInt64
    let policySHA256: String
}

private struct PrivacyReviewDecodeEnvelopeV1: Decodable {
    let manifestID: UUID
    let manifestRevision: UInt64
    let manifestSHA256: String
    let policyID: UUID
    let policyRevision: UInt64
    let policySHA256: String
}
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

enum C30EvidenceContextPackageValidationV1 {
    static let canonicalBytesRequired = true
    static let crossWorkspaceRowsRejected = true
    static let inferredContextRejected = true

    static func validate(_ rows: [V30BackupEvidenceContextRecordV1]) throws {
        guard canonicalBytesRequired, crossWorkspaceRowsRejected,
              inferredContextRejected else { throw BackupPackageValidationErrorV1.invalidPackage }
        _ = try EvidenceContextBackupRecordSetV1.decode(rows)
    }

    static func validate(_ records: V4BackupRecordsV1) throws {
        guard canonicalBytesRequired, crossWorkspaceRowsRejected,
              inferredContextRejected else { throw BackupPackageValidationErrorV1.invalidPackage }
        do {
            try records.validateC30EvidenceContextClosure()
        } catch {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }
}

/// C31 package boundary for the five durable lighting roots.  Lighting rows
/// are transported only as canonical bytes; validation never derives a
/// measurement, claim, or compliance conclusion from media or report text.
enum C31LightingPackageValidationV1 {
    static let persistentSchemaVersion = 31
    static let recordsSchemaVersion = 30
    static let durableFamilyCount = 5
    static let canonicalBytesRequired = true
    static let derivedProjectionsExcluded = true

    static func validate(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= recordsSchemaVersion else {
            guard records.lighting.isEmpty else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            return
        }
        guard canonicalBytesRequired, derivedProjectionsExcluded,
              (records.recordsSchemaVersion == recordsSchemaVersion || records.recordsSchemaVersion == 31
                || records.recordsSchemaVersion == 32 || records.recordsSchemaVersion == 33 || records.recordsSchemaVersion == 34
                || records.recordsSchemaVersion == C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion
                || records.recordsSchemaVersion == C49BackupEnrollmentV1.recordsSchemaVersion
                || records.recordsSchemaVersion == 37
                || records.recordsSchemaVersion == C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion) else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        do {
            try records.validateC31LightingClosure()
            guard V31BackupLightingRecordV1.Kind.allCases.count == durableFamilyCount else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        } catch {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }
}

/// C32 validates only immutable acceptance provenance. The package format has
/// no proposal, rejected/cancelled corpus, or leased-scratch member to admit.
enum C32AssistancePackageValidationV1 {
    static let persistentSchemaVersion = 32
    static let recordsSchemaVersion = 31
    static let durableFamilyCount = 1
    static let proposalsExcluded = true

    static func validate(_ records: V4BackupRecordsV1, manifest: V4BackupManifestV1) throws {
        guard records.recordsSchemaVersion >= recordsSchemaVersion else {
            guard records.assistanceAcceptanceReceipts.isEmpty else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            return
        }
        guard manifest.source.persistentSchemaVersion == records.recordsSchemaVersion + 1,
              manifest.source.recordsSchemaVersion == records.recordsSchemaVersion,
              (31...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              durableFamilyCount == AssistancePersistenceEnrollmentV1.durableModelCount,
              proposalsExcluded else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        do { try records.validateC32AssistanceAcceptanceReceipts() }
        catch { throw BackupPackageValidationErrorV1.invalidPackage }
    }
}

enum C33TemporalEvidencePackageValidationV1 {
    static func validate(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1
    ) throws {
        guard records.recordsSchemaVersion >= TemporalEvidencePersistenceEnrollmentV1.recordsSchemaVersion else {
            guard records.temporalEvidence.isEmpty else { throw BackupPackageValidationErrorV1.invalidPackage }
            return
        }
        guard (TemporalEvidencePersistenceEnrollmentV1.recordsSchemaVersion...
            C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              manifest.source.persistentSchemaVersion == records.recordsSchemaVersion + 1,
              manifest.source.recordsSchemaVersion == records.recordsSchemaVersion,
              let sourceWorkspaceID = manifest.source.workspaceID else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        do {
            let values = try records.validateC33TemporalEvidence()
            let clipsByID = Dictionary(uniqueKeysWithValues: values.clips.map { ($0.clipID, $0) })
            let anchorsByID = Dictionary(uniqueKeysWithValues: values.anchors.map { ($0.anchorID, $0) })
            for clip in values.clips {
                guard clip.workspaceID.rawValue == sourceWorkspaceID,
                      let digest = clip.original.digests.digest(for: .sha256)?.hexadecimalValue else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
                let path = try TemporalEvidenceBackupMemberV1.original(for: clip)
                guard let descriptor = members.descriptors[path],
                      descriptor.byteCount == clip.original.byteLength,
                      descriptor.sha256 == digest,
                      descriptor.mimeType == clip.original.mediaType,
                      let bytes = members[path],
                      Int64(bytes.count) == clip.original.byteLength,
                      CanonicalJSONV1.sha256(bytes) == digest else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
            }
            for report in records.reports {
                guard let snapshotBytes = members[report.snapshotRelativePath] else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
                if report.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion {
                    _ = try CompletedActivitySnapshotCanonicalCodecV2.decode(snapshotBytes)
                    continue
                }
                let snapshot = try ReportSnapshotEncoderV1().decode(snapshotBytes)
                for link in snapshot.temporalEvidenceLinks ?? [] {
                    guard link.workspaceID.rawValue == sourceWorkspaceID,
                          let clip = clipsByID[link.clipID] else {
                        throw BackupPackageValidationErrorV1.invalidPackage
                    }
                    let anchors = try link.anchorBindings.map { binding in
                        guard let anchor = anchorsByID[binding.anchorID],
                              try binding.matches(anchor, clip: clip) else {
                            throw BackupPackageValidationErrorV1.invalidPackage
                        }
                        return anchor
                    }
                    try link.validate(clip: clip, anchors: anchors)
                }
            }
        } catch {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }
}

enum C45AssetLabelPackageValidationV1 {
    static func validate(_ records: V4BackupRecordsV1, manifest: V4BackupManifestV1) throws {
        guard records.recordsSchemaVersion >= AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion else {
            guard records.acceptedLabelGenerationSnapshots.isEmpty else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            return
        }
        guard (AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion...
                C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion),
              manifest.source.persistentSchemaVersion == records.recordsSchemaVersion + 1,
              manifest.source.recordsSchemaVersion == records.recordsSchemaVersion,
              let sourceWorkspaceID = manifest.source.workspaceID else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        do {
            let values = try records.validateC45AcceptedLabelSnapshots()
            guard values.allSatisfy({ $0.workspaceID.rawValue == sourceWorkspaceID }) else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        } catch { throw BackupPackageValidationErrorV1.invalidPackage }
    }
}

enum C46OperationalContactPackageValidationV1 {
    static func validate(_ records: V4BackupRecordsV1, manifest: V4BackupManifestV1) throws {
        guard records.recordsSchemaVersion >= OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion else {
            guard records.operationalContacts.isEmpty else { throw BackupPackageValidationErrorV1.invalidPackage }
            return
        }
        guard (OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion...
                C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion),
              manifest.source.persistentSchemaVersion == records.recordsSchemaVersion + 1,
              manifest.source.recordsSchemaVersion == records.recordsSchemaVersion,
              let sourceWorkspaceID = manifest.source.workspaceID else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        do {
            let values = try records.validateC46OperationalContacts()
            guard values.contacts.allSatisfy({ $0.workspaceID.rawValue == sourceWorkspaceID }),
                  values.intents.allSatisfy({ $0.workspaceID.rawValue == sourceWorkspaceID }) else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        } catch { throw BackupPackageValidationErrorV1.invalidPackage }
    }
}

enum C47ActivityContractPackageValidationV2 {
    static func validate(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1
    ) throws {
        guard records.recordsSchemaVersion >= C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion else {
            guard records.activityContracts.isEmpty else { throw BackupPackageValidationErrorV1.invalidPackage }
            return
        }
        guard (C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion...
                C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              manifest.source.persistentSchemaVersion == records.recordsSchemaVersion + 1,
              manifest.source.recordsSchemaVersion == records.recordsSchemaVersion,
              let sourceWorkspaceID = manifest.source.workspaceID else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        do {
            let values = try records.validateC47ActivityContracts()
            guard (values.envelopes.map(\.workspaceID) + values.transitions.map(\.workspaceID)
                    + values.taskResults.map(\.workspaceID) + values.asBuilt.map(\.workspaceID)
                    + values.punchBasis.map(\.workspaceID))
                .allSatisfy({ $0.rawValue == sourceWorkspaceID }) else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            let completedSnapshots = try records.reports.compactMap {
                report -> CompletedActivitySnapshotV2? in
                guard report.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion else {
                    return nil
                }
                guard let data = members[report.snapshotRelativePath],
                      CanonicalJSONV1.sha256(data) == report.snapshotSHA256 else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
                return try CompletedActivitySnapshotCanonicalCodecV2.decode(data)
            }
            let references = try records.mutationHistory?.receipts.compactMap {
                record -> CompletedActivitySnapshotV2CompatibilityReferenceV1? in
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                guard case let .applyActivityContract(mutation) = envelope.command else { return nil }
                return mutation.completedSnapshotReference
            } ?? []
            for reference in references {
                let matches = completedSnapshots.filter {
                    (try? reference.validate(snapshot: $0)) != nil
                }
                guard matches.count == 1 else {
                    throw BackupPackageValidationErrorV1.invalidPackage
                }
            }
        } catch { throw BackupPackageValidationErrorV1.invalidPackage }
    }
}

enum C49WorkResourcePackageValidationV1 {
    static func validate(_ records: V4BackupRecordsV1, manifest: V4BackupManifestV1) throws {
        guard records.recordsSchemaVersion >= C49BackupEnrollmentV1.recordsSchemaVersion else {
            guard records.workResources.isEmpty else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            return
        }
        guard records.recordsSchemaVersion <= C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion,
              manifest.source.persistentSchemaVersion == records.recordsSchemaVersion + 1,
              manifest.source.recordsSchemaVersion == records.recordsSchemaVersion,
              let sourceWorkspaceID = manifest.source.workspaceID else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        do {
            let entries = try records.validateC49WorkResources()
            guard entries.allSatisfy({ $0.workspaceID.rawValue == sourceWorkspaceID }) else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        } catch { throw BackupPackageValidationErrorV1.invalidPackage }
    }
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
        try C34SceneNavigationPackageValidationBoundaryV1.validate()
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
        try validateGraph(records, manifest: manifest, members: members)
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
                guard ["media", "thumbnails", "snapshots", "pdfs", "draft-staging"].contains(name),
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
                    guard childFolded.insert(fold(childName)).inserted else {
                        throw BackupPackageValidationErrorV1.invalidPackage
                    }
                    if name == "draft-staging" {
                        guard canonicalUUIDComponent(childName), try itemType(child) == .directory else {
                            throw BackupPackageValidationErrorV1.invalidPackage
                        }
                        let stageFiles = try fileManager.contentsOfDirectory(at:child,includingPropertiesForKeys:nil,options:[])
                        guard !stageFiles.isEmpty else { throw BackupPackageValidationErrorV1.invalidPackage }
                        var stageFolded=Set<String>()
                        for stageFile in stageFiles {
                            let stageName=stageFile.lastPathComponent
                            try validateComponent(stageName)
                            let stem=String(stageName.dropLast(4))
                            guard stageName.hasSuffix(".bin"),canonicalUUIDComponent(stem),stageFolded.insert(fold(stageName)).inserted,try itemType(stageFile) == .regular,
                                  result.files.insert("\(name)/\(childName)/\(stageName)").inserted else{throw BackupPackageValidationErrorV1.invalidPackage}
                        }
                        continue
                    }
                    guard try itemType(child) == .regular else { throw BackupPackageValidationErrorV1.invalidPackage }
                    let relative = "\(name)/\(childName)"
                    guard result.files.insert(relative).inserted else {
                        throw BackupPackageValidationErrorV1.invalidPackage
                    }
                }
            }
        }
        return result
    }

    func canonicalUUIDComponent(_ value:String)->Bool{
        guard let id=UUID(uuidString:value) else{return false}
        return id.uuidString.lowercased()==value
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
             (4, 5, 4), (4, 6, 5), (4, 7, 6), (4, 8, 7), (4, 9, 8),
             (4, 10, 9), (4, 11, 10), (4, 12, 11), (4, 13, 12),
             (4, 14, 13), (4, 15, 14), (4, 16, 15), (4, 17, 16), (4, 18, 17), (4, 19, 18), (4, 20, 19), (4, 21, 20), (4, 22, 21), (4, 23, 22), (4, 24, 23), (4, 25, 24), (4, 26, 25), (4, 27, 26), (4, 28, 27), (4, 29, 28), (4, 30, 29), (4, 31, 30), (4, 32, 31), (4, 33, 32), (4, 34, 33), (4, 35, 34), (4, 36, 35), (4, 37, 36):
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
        manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1
    ) throws {
        try KernelBackupRestoreRegistryV4.validate()
        let kernelSchema = try KernelPersistenceV4Schema.descriptor()
        guard kernelSchema.runtimePosture == .dormantStatic,
              !kernelSchema.activationEnabled else { throw invalid() }
        try validateDeletionLedger(records, manifest: manifest)
        try validateObservationAndTime(records)
        try validateLocationRecords(records, manifest: manifest)
        try validatePartyAccountability(records, manifest: manifest)
        try validatePackageEvolution(records, manifest: manifest)
        try validateMeasurementIntegrity(records, manifest: manifest)
        try validatePrivacyTransforms(records, manifest: manifest)
        try validateClientCapabilities(records, manifest: manifest)
        try validateRecoverabilityReceipts(records, manifest: manifest)
        try validateFieldReferences(records,manifest:manifest)
        try validateAccessibleDocumentAssessments(records,manifest:manifest,members:members)
        try validateSurveyDefinitions(records, manifest: manifest)
        try validateGuidedSurveys(records,manifest:manifest)
        try validateAssetLocators(records, manifest: manifest)
        try validateSchedules(records, manifest: manifest)
        try validatePlans(records, manifest: manifest)
        try validatePlacementPoses(records, manifest: manifest)
        try validateLighting(records, manifest: manifest)
        try C30EvidenceContextPackageValidationV1.validate(records)
        try C31LightingPackageValidationV1.validate(records)
        try C32AssistancePackageValidationV1.validate(records, manifest: manifest)
        try C33TemporalEvidencePackageValidationV1.validate(
            records, manifest: manifest, members: members
        )
        try C45AssetLabelPackageValidationV1.validate(records, manifest: manifest)
        try C46OperationalContactPackageValidationV1.validate(records, manifest: manifest)
        try C47ActivityContractPackageValidationV2.validate(
            records, manifest: manifest, members: members
        )
        try C49WorkResourcePackageValidationV1.validate(records, manifest: manifest)
        try C52ServiceRequestBackupDecodingBoundaryV1.validate(records)
        try C53ServiceReliabilityBackupPackageValidationV1.validate(records, manifest: manifest)
        _ = try C48PortableExchangeBackupPackageValidationV2.snapshot(
            manifest: manifest,
            members: members
        )
        try validateAssetSemantics(records, manifest: manifest)
        try validateAuthorityCriterion(records, manifest: manifest)
        try validateFunctionalRelationships(records, manifest: manifest)
        try validateEvidenceAssurance(records, manifest: manifest, members: members)
        try validateInspectionReview(records, manifest: manifest, members: members)
        try validateWorkPackets(records, manifest: manifest, members: members)
        try validateFieldDrafts(records, manifest: manifest, members: members)
        let savedSmartViews: [SavedSmartViewDescriptorV1]
        do {
            savedSmartViews = try records.savedSmartViews.map { try $0.descriptor() }
        } catch {
            throw invalid()
        }
        guard records.recordsSchemaVersion < 6
                ? savedSmartViews.isEmpty
                : ((records.recordsSchemaVersion == 6
                        || records.recordsSchemaVersion == 7
                        || records.recordsSchemaVersion == 8
                        || records.recordsSchemaVersion == 9
                        || records.recordsSchemaVersion == 10
                        || records.recordsSchemaVersion == 11
                        || records.recordsSchemaVersion == 12
                        || records.recordsSchemaVersion == 13
                        || records.recordsSchemaVersion == 14
                        || records.recordsSchemaVersion == 15
                        || records.recordsSchemaVersion == 16
                        || records.recordsSchemaVersion == 17
                        || records.recordsSchemaVersion == 18
                        || records.recordsSchemaVersion == 19
                        || records.recordsSchemaVersion == 20 || records.recordsSchemaVersion == 21 || records.recordsSchemaVersion == 22 || records.recordsSchemaVersion == 23 || records.recordsSchemaVersion == 24 || records.recordsSchemaVersion == 25 || records.recordsSchemaVersion == 26 || records.recordsSchemaVersion == 27 || records.recordsSchemaVersion == 28 || records.recordsSchemaVersion == 29 || records.recordsSchemaVersion == 30 || records.recordsSchemaVersion == 31 || records.recordsSchemaVersion == 32 || records.recordsSchemaVersion == 33 || records.recordsSchemaVersion == 34 || records.recordsSchemaVersion == 35 || records.recordsSchemaVersion == 36 || records.recordsSchemaVersion == 37 || records.recordsSchemaVersion == 38 || records.recordsSchemaVersion == 39)
                    && savedSmartViews.allSatisfy({
                        $0.workspaceID == manifest.source.workspaceID
                    })) else {
            throw invalid()
        }
        let assuranceSnapshots: [RequirementAssuranceSnapshotV1]
        do {
            assuranceSnapshots = try records.requirementAssurance.map { try $0.snapshot() }
        } catch { throw invalid() }
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
              records.recordsSchemaVersion < 7
                ? assuranceSnapshots.isEmpty
                : ((records.recordsSchemaVersion == 7 || records.recordsSchemaVersion == 8
                        || records.recordsSchemaVersion == 9
                        || records.recordsSchemaVersion == 10
                        || records.recordsSchemaVersion == 11
                        || records.recordsSchemaVersion == 12
                        || records.recordsSchemaVersion == 13
                        || records.recordsSchemaVersion == 14
                        || records.recordsSchemaVersion == 15
                        || records.recordsSchemaVersion == 16
                        || records.recordsSchemaVersion == 17
                        || records.recordsSchemaVersion == 18
                        || records.recordsSchemaVersion == 19
                        || records.recordsSchemaVersion == 20 || records.recordsSchemaVersion == 21 || records.recordsSchemaVersion == 22 || records.recordsSchemaVersion == 23 || records.recordsSchemaVersion == 24 || records.recordsSchemaVersion == 25 || records.recordsSchemaVersion == 26 || records.recordsSchemaVersion == 27 || records.recordsSchemaVersion == 28 || records.recordsSchemaVersion == 29 || records.recordsSchemaVersion == 30 || records.recordsSchemaVersion == 31 || records.recordsSchemaVersion == 32 || records.recordsSchemaVersion == 33 || records.recordsSchemaVersion == 34 || records.recordsSchemaVersion == 35 || records.recordsSchemaVersion == 36 || records.recordsSchemaVersion == 37 || records.recordsSchemaVersion == 38 || records.recordsSchemaVersion == 39)
                    && assuranceSnapshots.allSatisfy({ snapshot in
                        snapshot.workspaceID == manifest.source.workspaceID
                            && workflow[snapshot.workflowRecordID] != nil
                    })
                    && Set(assuranceSnapshots.map(\.workflowRecordID))
                        == Set(records.workflowRecords.map(\.id))
                    && Set(assuranceSnapshots.map(\.workflowRecordID)).count
                        == assuranceSnapshots.count),
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
        guard (4...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { throw invalid() }
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

    func validatePartyAccountability(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 8 else {
            guard records.partyAccountability.isEmpty else { throw invalid() }
            return
        }
        guard (8...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              (manifest.source.persistentSchemaVersion == 9
                || manifest.source.persistentSchemaVersion == 10
                || manifest.source.persistentSchemaVersion == 11
                || manifest.source.persistentSchemaVersion == 12
                || manifest.source.persistentSchemaVersion == 13
                || manifest.source.persistentSchemaVersion == 14
                || manifest.source.persistentSchemaVersion == 15
                || manifest.source.persistentSchemaVersion == 16
                || manifest.source.persistentSchemaVersion == 17
                || manifest.source.persistentSchemaVersion == 18
                || manifest.source.persistentSchemaVersion == 19
                || manifest.source.persistentSchemaVersion == 20
                || manifest.source.persistentSchemaVersion == 21 || manifest.source.persistentSchemaVersion == 22 || manifest.source.persistentSchemaVersion == 23 || manifest.source.persistentSchemaVersion == 24 || manifest.source.persistentSchemaVersion == 25 || manifest.source.persistentSchemaVersion == 26 || manifest.source.persistentSchemaVersion == 27 || manifest.source.persistentSchemaVersion == 28 || manifest.source.persistentSchemaVersion == 29 || manifest.source.persistentSchemaVersion == 30 || manifest.source.persistentSchemaVersion == 31 || manifest.source.persistentSchemaVersion == 32 || manifest.source.persistentSchemaVersion == 33 || manifest.source.persistentSchemaVersion == 34 || manifest.source.persistentSchemaVersion == 35 || manifest.source.persistentSchemaVersion == 36 || manifest.source.persistentSchemaVersion == 37 || manifest.source.persistentSchemaVersion == 38 || manifest.source.persistentSchemaVersion == 39),
              let workspaceID = manifest.source.workspaceID else { throw invalid() }
        let keys = records.partyAccountability.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        guard keys == keys.sorted(), Set(keys).count == keys.count,
              records.partyAccountability.allSatisfy({
                  $0.id != zero && $0.workspaceID == workspaceID
                      && ($0.revision.map { $0 > 0 } ?? true) && !$0.canonicalData.isEmpty
              }) else { throw invalid() }
        do {
            var parties = Set<UUID>()
            var roles: [SitePartyRoleEventV1] = []
            var actors: [UUID: ActorSnapshotV1] = [:]
            var qualifications: [UUID: QualificationSnapshotV1] = [:]
            var signoffs: [SignoffSnapshotV1] = []
            for row in records.partyAccountability {
                switch row.kind {
                case .serviceParty:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        ServicePartyReferenceV1.self, from: row.canonicalData
                    )
                    guard value.partyID == row.id, value.workspaceID.rawValue == row.workspaceID,
                          value.revision == row.revision else { throw invalid() }
                    parties.insert(value.partyID)
                case .sitePartyRoleEvent:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        SitePartyRoleEventV1.self, from: row.canonicalData
                    )
                    guard value.eventID == row.id, value.workspaceID.rawValue == row.workspaceID,
                          value.revision == row.revision else { throw invalid() }
                    roles.append(value)
                case .actorSnapshot:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        ActorSnapshotV1.self, from: row.canonicalData
                    )
                    guard value.snapshotID == row.id, value.workspaceID.rawValue == row.workspaceID,
                          row.revision == nil else { throw invalid() }
                    actors[value.snapshotID] = value
                case .qualificationSnapshot:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        QualificationSnapshotV1.self, from: row.canonicalData
                    )
                    guard value.snapshotID == row.id, value.workspaceID.rawValue == row.workspaceID,
                          row.revision == nil else { throw invalid() }
                    qualifications[value.snapshotID] = value
                case .signoffSnapshot:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        SignoffSnapshotV1.self, from: row.canonicalData
                    )
                    guard value.snapshotID == row.id, value.workspaceID.rawValue == row.workspaceID,
                          value.subjectRevision == row.revision else { throw invalid() }
                    signoffs.append(value)
                }
            }
            let siteIDs = Set(records.sites.map(\.id))
            guard roles.allSatisfy({ parties.contains($0.partyID) && siteIDs.contains($0.siteID) }),
                  actors.values.allSatisfy({ snapshot in
                      snapshot.workspaceID.rawValue == workspaceID
                          && snapshot.actor.workspaceID.rawValue == workspaceID
                          && (snapshot.actor.partyID.map(parties.contains) ?? true)
                  }),
                  signoffs.allSatisfy({ snapshot in
                      (snapshot.roleAssertion.map {
                          actors[$0.actor.snapshotID] == $0.actor
                      } ?? true)
                          && (snapshot.qualification.map {
                              qualifications[$0.snapshotID] == $0
                          } ?? true)
                  }) else { throw invalid() }
        } catch { throw invalid() }
    }

    func validateAssetSemantics(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 9 else {
            guard records.assetSemantics.isEmpty else { throw invalid() }
            return
        }
        guard (9...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              (manifest.source.persistentSchemaVersion == 10
                || manifest.source.persistentSchemaVersion == 11
                || manifest.source.persistentSchemaVersion == 12
                || manifest.source.persistentSchemaVersion == 13
                || manifest.source.persistentSchemaVersion == 14
                || manifest.source.persistentSchemaVersion == 15
                || manifest.source.persistentSchemaVersion == 16
                || manifest.source.persistentSchemaVersion == 17
                || manifest.source.persistentSchemaVersion == 18
                || manifest.source.persistentSchemaVersion == 19
                || manifest.source.persistentSchemaVersion == 20
                || manifest.source.persistentSchemaVersion == 21 || manifest.source.persistentSchemaVersion == 22 || manifest.source.persistentSchemaVersion == 23 || manifest.source.persistentSchemaVersion == 24 || manifest.source.persistentSchemaVersion == 25 || manifest.source.persistentSchemaVersion == 26 || manifest.source.persistentSchemaVersion == 27 || manifest.source.persistentSchemaVersion == 28 || manifest.source.persistentSchemaVersion == 29 || manifest.source.persistentSchemaVersion == 30 || manifest.source.persistentSchemaVersion == 31 || manifest.source.persistentSchemaVersion == 32 || manifest.source.persistentSchemaVersion == 33 || manifest.source.persistentSchemaVersion == 34 || manifest.source.persistentSchemaVersion == 35 || manifest.source.persistentSchemaVersion == 36 || manifest.source.persistentSchemaVersion == 37 || manifest.source.persistentSchemaVersion == 38 || manifest.source.persistentSchemaVersion == 39),
              let sourceWorkspaceID = manifest.source.workspaceID else { throw invalid() }
        let keys = records.assetSemantics.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        guard keys == keys.sorted(), Set(keys).count == keys.count,
              records.assetSemantics.allSatisfy({
                  $0.workspaceID == sourceWorkspaceID && $0.revision > 0
                      && $0.revision <= UInt64(Int64.max) && !$0.canonicalData.isEmpty
              }) else { throw invalid() }
        do {
            var kinds: [UUID: AssetKindBindingEventV1] = [:]
            var workflowBindings: [UUID: AssetWorkflowCapabilityBindingEventV1] = [:]
            var identities: [UUID: AssetProductIdentityV1] = [:]
            var lifecycle: [UUID: AssetLifecycleEventV1] = [:]
            var successors: [UUID: AssetSuccessorLinkV1] = [:]
            var scopes: [UUID: WorkSubjectScopeSnapshotV1] = [:]
            for row in records.assetSemantics {
                switch row.kind {
                case .kindBindingEvent:
                    let value = try AssetSemanticCanonicalCodecV1.decode(
                        AssetKindBindingEventV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.eventID == row.id,
                          value.workspaceID.rawValue == row.workspaceID,
                          value.revision == row.revision,
                          kinds.updateValue(value, forKey: value.eventID) == nil else { throw invalid() }
                case .workflowCapabilityBindingEvent:
                    let value = try AssetSemanticCanonicalCodecV1.decode(
                        AssetWorkflowCapabilityBindingEventV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.eventID == row.id,
                          value.workspaceID.rawValue == row.workspaceID,
                          value.revision == row.revision,
                          workflowBindings.updateValue(value, forKey: value.eventID) == nil else { throw invalid() }
                case .productIdentity:
                    let value = try AssetSemanticCanonicalCodecV1.decode(
                        AssetProductIdentityV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.identityID == row.id,
                          value.workspaceID.rawValue == row.workspaceID,
                          value.revision == row.revision,
                          identities.updateValue(value, forKey: value.identityID) == nil else { throw invalid() }
                case .lifecycleEvent:
                    let value = try AssetSemanticCanonicalCodecV1.decode(
                        AssetLifecycleEventV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.record.eventID == row.id,
                          value.record.workspaceID.rawValue == row.workspaceID,
                          value.record.revision == row.revision,
                          lifecycle.updateValue(value, forKey: value.record.eventID) == nil else { throw invalid() }
                case .successorLink:
                    let value = try AssetSemanticCanonicalCodecV1.decode(
                        AssetSuccessorLinkV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.linkID == row.id,
                          value.workspaceID.rawValue == row.workspaceID,
                          value.revision == row.revision,
                          successors.updateValue(value, forKey: value.linkID) == nil else { throw invalid() }
                case .workSubjectScopeSnapshot:
                    let value = try AssetSemanticCanonicalCodecV1.decode(
                        WorkSubjectScopeSnapshotV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.snapshotID == row.id,
                          value.workspaceID.rawValue == row.workspaceID,
                          value.workspaceRevision == row.revision,
                          scopes.updateValue(value, forKey: value.snapshotID) == nil else { throw invalid() }
                }
            }
            let deletionEntries = records.deletionLedger?.entries ?? []
            let deletedAssetIDs = Set(deletionEntries.compactMap {
                $0.identity.kind == .asset ? $0.identity.id : nil
            })
            let deletedSiteIDs = Set(deletionEntries.compactMap {
                $0.identity.kind == .site ? $0.identity.id : nil
            })
            let assetIDs = Set(records.assets.map(\.id)).union(deletedAssetIDs)
            let siteIDs = Set(records.sites.map(\.id)).union(deletedSiteIDs)
            let locationIDs = Set(records.locationNodes.map(\.id))
            let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
            let declaredReleases = Set(try manifest.packs.map {
                try releaseIdentity(packageID: $0.id, schemaVersion: $0.schemaVersion,
                                    contentVersion: $0.contentVersion)
            })
            guard kinds.values.allSatisfy({ value in
                      assetIDs.contains(value.assetID)
                        && declaredReleases.contains(value.catalogRelease.packageRelease)
                        && (value.predecessorEventID.map { predecessorID in
                            guard let predecessor = kinds[predecessorID] else { return false }
                            return predecessor.assetID == value.assetID
                                && predecessor.workspaceID == value.workspaceID
                                && predecessor.revision < value.revision
                        } ?? true)
                  }),
                  workflowBindings.values.allSatisfy({ value in
                      guard assetIDs.contains(value.assetID),
                            let kind = kinds[value.kindBindingEventID] else { return false }
                      return kind.assetID == value.assetID
                        && kind.workspaceID == value.workspaceID
                        && kind.revision == value.kindBindingRevision
                        && declaredReleases.contains(value.workflowPackageRelease)
                        && (value.predecessorEventID.map { predecessorID in
                            guard let predecessor = workflowBindings[predecessorID] else { return false }
                            return predecessor.assetID == value.assetID
                                && predecessor.workspaceID == value.workspaceID
                                && predecessor.revision < value.revision
                        } ?? true)
                  }),
                  identities.values.allSatisfy({ value in
                      assetIDs.contains(value.assetID)
                        && (value.predecessorIdentityID.map { predecessorID in
                            guard let predecessor = identities[predecessorID] else { return false }
                            return predecessor.assetID == value.assetID
                                && predecessor.workspaceID == value.workspaceID
                                && predecessor.revision < value.revision
                        } ?? true)
                  }),
                  successors.values.allSatisfy({ value in
                      assetIDs.contains(value.predecessorAssetID)
                        && assetIDs.contains(value.successorAssetID)
                        && (value.predecessorLinkID.map { predecessorID in
                            guard let predecessor = successors[predecessorID] else { return false }
                            return predecessor.workspaceID == value.workspaceID
                                && predecessor.revision < value.revision
                        } ?? true)
                  }) else { throw invalid() }
            try AssetSuccessorLinkV1.validateAcyclic(Array(successors.values))
            for value in lifecycle.values {
                let record = value.record
                guard assetIDs.contains(record.assetID),
                      record.predecessorEventID.map({ predecessorID in
                          guard let predecessor = lifecycle[predecessorID] else { return false }
                          return predecessor.record.assetID == record.assetID
                            && predecessor.record.workspaceID == record.workspaceID
                            && predecessor.record.revision < record.revision
                      }) ?? true else { throw invalid() }
                if value.kind == .classificationChangedRecorded {
                    guard let id = record.kindBindingEventID, let kind = kinds[id] else { throw invalid() }
                    try value.validateAtomicReference(kindBinding: kind)
                } else if value.kind == .replacedRecorded {
                    guard let id = record.successorLinkID, let link = successors[id] else { throw invalid() }
                    try value.validateAtomicReference(successorLink: link)
                }
            }
            for value in scopes.values {
                guard siteIDs.contains(value.siteID), value.subjects.allSatisfy({ subject in
                    switch subject.kind {
                    case .site: return subject.subjectID == value.siteID && siteIDs.contains(subject.subjectID)
                    case .locationNode: return locationIDs.contains(subject.subjectID)
                    case .asset: return assetIDs.contains(subject.subjectID)
                    case .compositionComponent:
                        return subject.subjectID != zero
                            && subject.ownerAssetID.map(assetIDs.contains) == true
                    case .functionalRelationship:
                        guard subject.ownerAssetID == nil,
                              let relationship = subject.functionalRelationship,
                              relationship.relationshipID == subject.subjectID,
                              relationship.relationshipRevision == subject.revision,
                              relationship.descriptorReleaseID != zero,
                              relationship.descriptorReleaseRevision > 0,
                              AssetSemanticValidationV1.validPackageRelease(
                                  relationship.packageRelease
                              ),
                              AssetSemanticValidationV1.validPackageRelease(
                                  relationship.semanticCatalogRelease.packageRelease
                              ),
                              (try? relationship.semanticCatalogRelease.validate()) != nil,
                              AssetSemanticValidationV1.validIdentifier(
                                  relationship.semanticID, maximumBytes: 160
                              ),
                              declaredReleases.contains(relationship.packageRelease),
                              declaredReleases.contains(
                                  relationship.semanticCatalogRelease.packageRelease
                              ) else { return false }
                        return true
                    }
                }), value.semanticBindings.allSatisfy({ binding in
                    guard assetIDs.contains(binding.assetID),
                          let kind = kinds[binding.kindBindingEventID] else { return false }
                    return kind.assetID == binding.assetID
                        && kind.revision == binding.kindBindingRevision
                        && kind.catalogRelease == binding.catalogRelease
                        && kind.semanticID == binding.semanticID
                        && binding.workflowPackageReleases.allSatisfy(declaredReleases.contains)
                }) else { throw invalid() }
            }
        } catch { throw invalid() }
    }

    func validateAuthorityCriterion(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 10 else {
            guard records.authorityCriterion.isEmpty else { throw invalid() }
            return
        }
        guard (10...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              (manifest.source.persistentSchemaVersion == 11
                || manifest.source.persistentSchemaVersion == 12
                || manifest.source.persistentSchemaVersion == 13
                || manifest.source.persistentSchemaVersion == 14
                || manifest.source.persistentSchemaVersion == 15
                || manifest.source.persistentSchemaVersion == 16
                || manifest.source.persistentSchemaVersion == 17
                || manifest.source.persistentSchemaVersion == 18
                || manifest.source.persistentSchemaVersion == 19
                || manifest.source.persistentSchemaVersion == 20
                || manifest.source.persistentSchemaVersion == 21 || manifest.source.persistentSchemaVersion == 22 || manifest.source.persistentSchemaVersion == 23 || manifest.source.persistentSchemaVersion == 24 || manifest.source.persistentSchemaVersion == 25 || manifest.source.persistentSchemaVersion == 26 || manifest.source.persistentSchemaVersion == 27 || manifest.source.persistentSchemaVersion == 28 || manifest.source.persistentSchemaVersion == 29 || manifest.source.persistentSchemaVersion == 30 || manifest.source.persistentSchemaVersion == 31 || manifest.source.persistentSchemaVersion == 32 || manifest.source.persistentSchemaVersion == 33 || manifest.source.persistentSchemaVersion == 34 || manifest.source.persistentSchemaVersion == 35 || manifest.source.persistentSchemaVersion == 36 || manifest.source.persistentSchemaVersion == 37 || manifest.source.persistentSchemaVersion == 38 || manifest.source.persistentSchemaVersion == 39),
              let workspaceID = manifest.source.workspaceID else { throw invalid() }
        let keys = records.authorityCriterion.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        guard keys == keys.sorted(), Set(keys).count == keys.count,
              records.authorityCriterion.allSatisfy({
                  $0.workspaceID == workspaceID && !$0.canonicalData.isEmpty
              }) else { throw invalid() }
        do {
            _ = try BackupCanonicalDecoderV1().decodeRecords(
                BackupCanonicalEncoderV1().encodeRecords(records).data
            )
            var sources: [UUID: AuthoritySourceReleaseV1] = [:]
            var bases: [UUID: RequirementBasisBindingV1] = [:]
            var contexts: [UUID: ApplicabilityContextSnapshotV1] = [:]
            var scopes: [UUID: AssessmentScopeSnapshotV1] = [:]
            var scales: [UUID: SeverityScaleReleaseV1] = [:]
            var classifications: [UUID: FindingClassificationBindingV1] = [:]
            var protocols: [UUID: MeasurementProtocolReleaseV1] = [:]
            var evaluators: [UUID: DerivedFactEvaluatorDescriptorV1] = [:]
            var facts: [UUID: DerivedFactProvenanceV1] = [:]
            for row in records.authorityCriterion {
                switch row.kind {
                case .authoritySourceRelease:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(AuthoritySourceReleaseV1.self, from: row.canonicalData)
                    guard value.releaseID == row.id, sources.updateValue(value, forKey: value.releaseID) == nil else { throw invalid() }
                case .requirementBasisBinding:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(RequirementBasisBindingV1.self, from: row.canonicalData)
                    guard value.bindingID == row.id, bases.updateValue(value, forKey: value.bindingID) == nil else { throw invalid() }
                case .applicabilityContextSnapshot:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(ApplicabilityContextSnapshotV1.self, from: row.canonicalData)
                    guard value.snapshotID == row.id, contexts.updateValue(value, forKey: value.snapshotID) == nil else { throw invalid() }
                case .assessmentScopeSnapshot:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(AssessmentScopeSnapshotV1.self, from: row.canonicalData)
                    guard value.snapshotID == row.id, scopes.updateValue(value, forKey: value.snapshotID) == nil else { throw invalid() }
                case .severityScaleRelease:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(SeverityScaleReleaseV1.self, from: row.canonicalData)
                    guard value.releaseID == row.id, scales.updateValue(value, forKey: value.releaseID) == nil else { throw invalid() }
                case .findingClassificationBinding:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: row.canonicalData)
                    guard value.bindingID == row.id, classifications.updateValue(value, forKey: value.bindingID) == nil else { throw invalid() }
                case .measurementProtocolRelease:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(MeasurementProtocolReleaseV1.self, from: row.canonicalData)
                    guard value.releaseID == row.id, protocols.updateValue(value, forKey: value.releaseID) == nil else { throw invalid() }
                case .derivedFactEvaluatorDescriptor:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactEvaluatorDescriptorV1.self, from: row.canonicalData)
                    guard value.descriptorID == row.id, evaluators.updateValue(value, forKey: value.descriptorID) == nil else { throw invalid() }
                case .derivedFactProvenance:
                    let value = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactProvenanceV1.self, from: row.canonicalData)
                    guard value.provenanceID == row.id, facts.updateValue(value, forKey: value.provenanceID) == nil else { throw invalid() }
                }
            }

            func validateChain<T>(
                _ values: [T], id: KeyPath<T, UUID>, predecessor: KeyPath<T, UUID?>,
                revision: KeyPath<T, UInt64>
            ) throws {
                let byID = Dictionary(uniqueKeysWithValues: values.map { ($0[keyPath: id], $0) })
                var claimedPredecessors = Set<UUID>()
                for value in values {
                    if let predecessorID = value[keyPath: predecessor] {
                        guard let prior = byID[predecessorID],
                              prior[keyPath: revision] < UInt64.max,
                              prior[keyPath: revision] + 1 == value[keyPath: revision],
                              claimedPredecessors.insert(predecessorID).inserted else { throw invalid() }
                    } else if value[keyPath: revision] != 1 {
                        throw invalid()
                    }
                }
                try requireAcyclic(values, id: id, next: predecessor)
            }

            try validateChain(Array(sources.values), id: \.releaseID, predecessor: \.supersedesReleaseID, revision: \.revision)
            try validateChain(Array(bases.values), id: \.bindingID, predecessor: \.supersedesBindingID, revision: \.revision)
            try validateChain(Array(contexts.values), id: \.snapshotID, predecessor: \.supersedesSnapshotID, revision: \.revision)
            try validateChain(Array(scopes.values), id: \.snapshotID, predecessor: \.supersedesSnapshotID, revision: \.revision)
            try validateChain(Array(scales.values), id: \.releaseID, predecessor: \.supersedesReleaseID, revision: \.revision)
            try validateChain(Array(classifications.values), id: \.bindingID, predecessor: \.supersedesBindingID, revision: \.revision)
            try validateChain(Array(protocols.values), id: \.releaseID, predecessor: \.supersedesReleaseID, revision: \.revision)
            try validateChain(Array(evaluators.values), id: \.descriptorID, predecessor: \.supersedesDescriptorID, revision: \.revision)
            try validateChain(Array(facts.values), id: \.provenanceID, predecessor: \.predecessorProvenanceID, revision: \.revision)

            var actors: [UUID: ActorSnapshotV1] = [:]
            var qualifications: [UUID: QualificationSnapshotV1] = [:]
            for row in records.partyAccountability {
                switch row.kind {
                case .actorSnapshot:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: row.canonicalData)
                    actors[value.snapshotID] = value
                case .qualificationSnapshot:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(QualificationSnapshotV1.self, from: row.canonicalData)
                    qualifications[value.snapshotID] = value
                default: break
                }
            }
            var workScopes: [UUID: WorkSubjectScopeSnapshotV1] = [:]
            for row in records.assetSemantics where row.kind == .workSubjectScopeSnapshot {
                let value = try AssetSemanticCanonicalCodecV1.decode(WorkSubjectScopeSnapshotV1.self, from: row.canonicalData)
                workScopes[value.snapshotID] = value
            }

            guard bases.values.allSatisfy({ value in
                      sources[value.authorityReleaseID] != nil
                        && actors[value.selectedBy.snapshotID] == value.selectedBy
                  }),
                  contexts.values.allSatisfy({ value in
                      workScopes[value.workSubjectScope.snapshotID] == value.workSubjectScope
                        && actors[value.actor.snapshotID] == value.actor
                        && (value.qualification.map { qualifications[$0.snapshotID] == $0 } ?? true)
                        && value.basisBindings.allSatisfy { bases[$0.bindingID] == $0 }
                  }),
                  scopes.values.allSatisfy({ value in
                      contexts[value.applicabilityContextID] != nil
                        && workScopes[value.workSubjectScope.snapshotID] == value.workSubjectScope
                  }),
                  classifications.values.allSatisfy({ value in
                      guard let context = contexts[value.applicabilityContextID],
                            let scope = scopes[value.assessmentScopeID],
                            scope.applicabilityContextID == context.snapshotID,
                            scope.includedCriterionIDs.contains(value.criterionID) else { return false }
                      if let releaseID = value.severityScaleReleaseID {
                          guard let levelID = value.severityLevelID,
                                scales[releaseID]?.levels.contains(where: { $0.levelID == levelID }) == true else { return false }
                      }
                      return true
                  }),
                  protocols.values.allSatisfy({ evaluators[$0.evaluatorDescriptorID] != nil }),
                  facts.values.allSatisfy({ value in
                      guard let protocolValue = protocols[value.protocolReleaseID],
                            let evaluator = evaluators[value.evaluatorDescriptorID] else { return false }
                      return protocolValue.evaluatorDescriptorID == evaluator.descriptorID
                  }) else { throw invalid() }
        } catch { throw invalid() }
    }

    func validateFunctionalRelationships(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 11 else {
            guard records.functionalRelationships.isEmpty else { throw invalid() }
            return
        }
        guard (11...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              (manifest.source.persistentSchemaVersion == 12
                || manifest.source.persistentSchemaVersion == 13
                || manifest.source.persistentSchemaVersion == 14
                || manifest.source.persistentSchemaVersion == 15
                || manifest.source.persistentSchemaVersion == 16
                || manifest.source.persistentSchemaVersion == 17
                || manifest.source.persistentSchemaVersion == 18
                || manifest.source.persistentSchemaVersion == 19
                || manifest.source.persistentSchemaVersion == 20
                || manifest.source.persistentSchemaVersion == 21 || manifest.source.persistentSchemaVersion == 22 || manifest.source.persistentSchemaVersion == 23 || manifest.source.persistentSchemaVersion == 24 || manifest.source.persistentSchemaVersion == 25 || manifest.source.persistentSchemaVersion == 26 || manifest.source.persistentSchemaVersion == 27 || manifest.source.persistentSchemaVersion == 28 || manifest.source.persistentSchemaVersion == 29 || manifest.source.persistentSchemaVersion == 30 || manifest.source.persistentSchemaVersion == 31 || manifest.source.persistentSchemaVersion == 32 || manifest.source.persistentSchemaVersion == 33 || manifest.source.persistentSchemaVersion == 34 || manifest.source.persistentSchemaVersion == 35 || manifest.source.persistentSchemaVersion == 36 || manifest.source.persistentSchemaVersion == 37 || manifest.source.persistentSchemaVersion == 38 || manifest.source.persistentSchemaVersion == 39),
              let sourceWorkspaceID = manifest.source.workspaceID else { throw invalid() }
        do {
            let workspaceID = WorkspaceID(rawValue: sourceWorkspaceID)
            var descriptors: [UUID: FunctionalRelationshipTypeDescriptorV1] = [:]
            var events: [UUID: AssetFunctionalRelationshipEventV1] = [:]
            for row in records.functionalRelationships {
                switch row.kind {
                case .descriptor:
                    let value = try FunctionalRelationshipCanonicalCodecV1.decode(
                        FunctionalRelationshipTypeDescriptorV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.descriptorReleaseID == row.id, value.workspaceID == workspaceID,
                          value.revision == row.revision,
                          descriptors.updateValue(value, forKey: value.descriptorReleaseID) == nil else { throw invalid() }
                case .event:
                    let value = try FunctionalRelationshipCanonicalCodecV1.decode(
                        AssetFunctionalRelationshipEventV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.eventID == row.id, value.workspaceID == workspaceID,
                          value.revision == row.revision,
                          events.updateValue(value, forKey: value.eventID) == nil else { throw invalid() }
                }
            }
            var claimedDescriptorPredecessors = Set<UUID>()
            for value in descriptors.values {
                if let predecessorID = value.supersedesDescriptorReleaseID {
                    guard let predecessor = descriptors[predecessorID],
                          claimedDescriptorPredecessors.insert(predecessorID).inserted else { throw invalid() }
                    try value.validateSuccessor(of: predecessor)
                } else if value.revision != 1 { throw invalid() }
            }
            try requireAcyclic(Array(descriptors.values), id: \.descriptorReleaseID,
                               next: \.supersedesDescriptorReleaseID)
            let deletedAssets = Set((records.deletionLedger?.entries ?? []).compactMap {
                $0.identity.kind == .asset ? $0.identity.id : nil
            })
            let assetIDs = Set(records.assets.map(\.id)).union(deletedAssets)
            guard events.values.allSatisfy({ value in
                guard let descriptor = descriptors[value.descriptor.descriptorReleaseID] else { return false }
                return value.descriptor == FunctionalRelationshipDescriptorReferenceV1(descriptor)
                    && assetIDs.contains(value.sourceAssetID)
                    && assetIDs.contains(value.targetAssetID)
            }) else { throw invalid() }
            _ = try FunctionalRelationshipProjectionBuilderV1.rebuild(
                workspaceID: workspaceID,
                events: Array(events.values),
                descriptors: Array(descriptors.values)
            )
        } catch { throw invalid() }
    }

    func validateEvidenceAssurance(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1
    ) throws {
        guard records.recordsSchemaVersion >= 12 else {
            guard records.evidenceAssurance.isEmpty else { throw invalid() }
            return
        }
        guard (12...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              (manifest.source.persistentSchemaVersion == 13 || manifest.source.persistentSchemaVersion == 14
                || manifest.source.persistentSchemaVersion == 15
                || manifest.source.persistentSchemaVersion == 16
                || manifest.source.persistentSchemaVersion == 17
                || manifest.source.persistentSchemaVersion == 18
                || manifest.source.persistentSchemaVersion == 19
                || manifest.source.persistentSchemaVersion == 20
                || manifest.source.persistentSchemaVersion == 21 || manifest.source.persistentSchemaVersion == 22 || manifest.source.persistentSchemaVersion == 23 || manifest.source.persistentSchemaVersion == 24 || manifest.source.persistentSchemaVersion == 25 || manifest.source.persistentSchemaVersion == 26 || manifest.source.persistentSchemaVersion == 27 || manifest.source.persistentSchemaVersion == 28 || manifest.source.persistentSchemaVersion == 29 || manifest.source.persistentSchemaVersion == 30 || manifest.source.persistentSchemaVersion == 31 || manifest.source.persistentSchemaVersion == 32 || manifest.source.persistentSchemaVersion == 33 || manifest.source.persistentSchemaVersion == 34 || manifest.source.persistentSchemaVersion == 35 || manifest.source.persistentSchemaVersion == 36 || manifest.source.persistentSchemaVersion == 37 || manifest.source.persistentSchemaVersion == 38 || manifest.source.persistentSchemaVersion == 39),
              let rawWorkspaceID = manifest.source.workspaceID else { throw invalid() }
        do {
            let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
            var visibilities: [UUID: EvidenceVisibilityV1] = [:]
            var links: [UUID: ClaimEvidenceLinkV1] = [:]
            var manifests: [UUID: AssuranceManifestV1] = [:]
            var attestations: [UUID: AttestationV1] = [:]
            for row in records.evidenceAssurance {
                switch row.kind {
                case .visibility:
                    let value = try EvidenceAssuranceCanonicalCodecV1.decode(EvidenceVisibilityV1.self, from: row.canonicalData)
                    guard value.visibilityID == row.id, value.workspaceID == workspaceID,
                          value.revision == row.revision,
                          visibilities.updateValue(value, forKey: value.visibilityID) == nil else { throw invalid() }
                case .evidenceLink:
                    let value = try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: row.canonicalData)
                    guard value.linkID == row.id, value.workspaceID == workspaceID,
                          value.revision == row.revision,
                          links.updateValue(value, forKey: value.linkID) == nil else { throw invalid() }
                case .manifest:
                    let value = try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: row.canonicalData)
                    guard value.manifestID == row.id, value.workspaceID == workspaceID,
                          value.revision == row.revision,
                          manifests.updateValue(value, forKey: value.manifestID) == nil else { throw invalid() }
                case .attestation:
                    let value = try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self, from: row.canonicalData)
                    guard value.attestationID == row.id, value.workspaceID == workspaceID,
                          value.revision == row.revision,
                          attestations.updateValue(value, forKey: value.attestationID) == nil else { throw invalid() }
                }
            }
            try validateEvidenceAssuranceChains(visibilities, links, manifests, attestations)
            for link in links.values {
                guard let visibility = visibilities[link.visibilityID] else { throw invalid() }
                try link.validate(visibility: visibility)
            }
            var previews: [UUID: AssuranceProjectionPreviewV1] = [:]
            for report in records.reports {
                guard let bytes = members[report.snapshotRelativePath] else { throw invalid() }
                if report.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion {
                    _ = try CompletedActivitySnapshotCanonicalCodecV2.decode(bytes)
                    continue
                }
                let snapshot = try ReportSnapshotEncoderV1().decode(bytes)
                guard let preview = snapshot.assurance?.preview else { continue }
                if let existing = previews[preview.previewID], existing != preview { throw invalid() }
                previews[preview.previewID] = preview
            }
            let supersededLinkIDs = Set(links.values.compactMap(\.supersedesLinkID))
            let supersededManifestIDs = Set(manifests.values.compactMap(\.supersedesManifestID))
            for value in manifests.values {
                let manifestLinks = value.includedLinks + value.excludedLinks
                let currentLinks = links.values.filter {
                    !supersededLinkIDs.contains($0.linkID)
                        && $0.decision.audience == value.audience
                }
                guard manifestLinks.allSatisfy({ links[$0.linkID] == $0 }),
                      let preview = previews[value.sourcePreviewID] else { throw invalid() }
                try value.validateFresh(preview: preview)
                if !supersededManifestIDs.contains(value.manifestID) {
                    guard Set(manifestLinks.map(\.linkID)) == Set(currentLinks.map(\.linkID)) else {
                        throw invalid()
                    }
                }
            }
            for value in attestations.values {
                guard let assuranceManifest = manifests[value.manifestID] else { throw invalid() }
                try value.validate(manifest: assuranceManifest)
            }
        } catch { throw invalid() }
    }

    func validateWorkPackets(
        _ records: V4BackupRecordsV1, manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1
    ) throws {
        guard records.recordsSchemaVersion >= 14 else { guard records.workPackets.isEmpty else { throw invalid() }; return }
        guard (14...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion), manifest.source.persistentSchemaVersion >= 15,
              let rawWorkspaceID=manifest.source.workspaceID,records.workPackets.count<=WorkPacketLimitsV1.maximumHistory else{throw invalid()}
        do {
            let workspaceID=WorkspaceID(rawValue:rawWorkspaceID)
            var manifests:[UUID:WorkPacketManifestV1]=[:],claims:[UUID:WorkItemClaimV1]=[:],leases:[UUID:WorkLeaseV1]=[:],releases:[UUID:WorkReleaseV1]=[:],handoffs:[UUID:WorkHandoffV1]=[:],actors:[UUID:ActorSnapshotV1]=[:]
            var exactReferences:[String:Set<String>]=[:]
            func add(_ family:String,_ id:String,_ revision:UInt64,_ sha:String){exactReferences["\(family)\u{0}\(UUID(uuidString:id)?.uuidString ?? id)",default:[]].insert("\(revision)\u{0}\(sha)")}
            func known(_ value:ReviewEvidenceReferenceV1)->Bool{let family:String;switch value.kind{case .claimEvidenceLink:family="claimEvidenceLink";case .verifiedRecheck:family="verifiedRecheck";case .completedActivitySnapshot:family="completedActivitySnapshot";case .requirementEvaluation:family="requirementEvaluation";case .functionalRelationshipSnapshot:family="functionalRelationshipSnapshot";case .externalEvidenceReference:family="externalEvidenceReference"};return exactReferences["\(family)\u{0}\(UUID(uuidString:value.referenceID)?.uuidString ?? value.referenceID)"]?.contains("\(value.revision)\u{0}\(value.sha256)")==true}
            for row in records.evidenceAssurance where row.kind == .evidenceLink{let v=try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self,from:row.canonicalData);add("claimEvidenceLink",v.linkID.uuidString,v.revision,v.linkSHA256)}
            for report in records.reports {
                guard let revision = UInt64(exactly: report.snapshotSchemaVersion),
                      let bytes = members[report.snapshotRelativePath] else { throw invalid() }
                if report.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion {
                    let snapshot = try CompletedActivitySnapshotCanonicalCodecV2.decode(bytes)
                    for id in [report.id.uuidString, snapshot.payload.activity.reportID,
                               snapshot.payload.activity.snapshotID,
                               snapshot.payload.activity.sourceActivityID] {
                        add("completedActivitySnapshot", id, revision, report.snapshotSHA256)
                    }
                    continue
                }
                let snapshot = try ReportSnapshotEncoderV1().decode(bytes)
                for id in [report.id.uuidString, snapshot.reportID.uuidString,
                           snapshot.sourceRecordID.uuidString, snapshot.stableRootID.uuidString] {
                    add("completedActivitySnapshot", id, revision, report.snapshotSHA256)
                }
                if let relationship = snapshot.functionalRelationships,
                   let relationshipRevision = UInt64(exactly: relationship.schemaVersion) {
                    add("functionalRelationshipSnapshot", relationship.snapshotID.uuidString,
                        relationshipRevision, relationship.snapshotSHA256)
                }
                for evaluation in snapshot.requirementAssurance?.evaluations ?? [] {
                    add("requirementEvaluation", evaluation.requirementID,
                        evaluation.evaluatedRevision,
                        try WorkspaceMutationCanonicalV1.sha256(evaluation))
                }
            }
            for evidence in records.evidenceFiles{add("externalEvidenceReference",evidence.id.uuidString,1,evidence.sha256)}
            for row in records.partyAccountability where row.kind == .actorSnapshot {let v=try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self,from:row.canonicalData);guard actors.updateValue(v,forKey:v.snapshotID)==nil else{throw invalid()}}
            func known(_ actor:ActorSnapshotV1)->Bool{actors[actor.snapshotID]==actor}
            for row in records.workPackets {
                guard row.workspaceID==rawWorkspaceID else{throw invalid()}
                switch row.kind {
                case .manifest:let v=try WorkPacketCanonicalCodecV1.decode(WorkPacketManifestV1.self,from:row.canonicalData);guard v.manifestID==row.id,v.workspaceID==workspaceID,v.revision==row.revision,known(v.creator),manifests.updateValue(v,forKey:v.manifestID)==nil else{throw invalid()}
                case .claim:let v=try WorkPacketCanonicalCodecV1.decode(WorkItemClaimV1.self,from:row.canonicalData);guard v.claimID==row.id,v.workspaceID==workspaceID,v.revision==row.revision,known(v.holder),claims.updateValue(v,forKey:v.claimID)==nil else{throw invalid()}
                case .lease:let v=try WorkPacketCanonicalCodecV1.decode(WorkLeaseV1.self,from:row.canonicalData);guard v.leaseID==row.id,v.workspaceID==workspaceID,v.revision==row.revision,known(v.holder),leases.updateValue(v,forKey:v.leaseID)==nil else{throw invalid()}
                case .release:let v=try WorkPacketCanonicalCodecV1.decode(WorkReleaseV1.self,from:row.canonicalData);guard v.releaseID==row.id,v.workspaceID==workspaceID,v.revision==row.revision,known(v.holder),releases.updateValue(v,forKey:v.releaseID)==nil else{throw invalid()}
                case .handoff:let v=try WorkPacketCanonicalCodecV1.decode(WorkHandoffV1.self,from:row.canonicalData);guard v.handoffID==row.id,v.workspaceID==workspaceID,v.revision==row.revision,known(v.fromHolder),known(v.toHolder),handoffs.updateValue(v,forKey:v.handoffID)==nil else{throw invalid()}
                }
            }
            let packetIDs=Set(records.packets.map(\.id));guard manifests.values.allSatisfy({packetIDs.contains($0.packetID)})else{throw invalid()}
            let manifestVersions=manifests.values.map{"\($0.packetID.uuidString)\u{0}\($0.packetVersion)"}
            let claimPredecessors=claims.values.compactMap(\.supersedesClaimID)
            let leasePredecessors=leases.values.compactMap(\.supersedesLeaseID)
            guard Set(manifestVersions).count==manifestVersions.count,
                  Set(claimPredecessors).count==claimPredecessors.count,
                  Set(leasePredecessors).count==leasePredecessors.count else{throw invalid()}
            for claim in claims.values {guard let owner=manifests[claim.manifest.manifestID],claim.manifest==(try WorkPacketManifestReferenceV1(owner)),owner.items.contains(where:{(try? WorkPacketItemReferenceV1(manifest:owner,item:$0))==claim.item})else{throw invalid()};if let p=claim.supersedesClaimID{guard let prior=claims[p]else{throw invalid()};try claim.validateSuccessor(of:prior)}}
            for lease in leases.values {guard let claim=claims[lease.claimID],lease.item==claim.item else{throw invalid()};if let p=lease.supersedesLeaseID{guard let prior=leases[p]else{throw invalid()};try lease.validateSuccessor(of:prior)}}
            for release in releases.values {guard let c=claims[release.claimID],let l=leases[release.leaseID],let m=manifests[c.manifest.manifestID],release.resultLinks.allSatisfy({$0.evidence.allSatisfy(known)})else{throw invalid()};try release.validate(claim:c,lease:l,manifest:m)}
            for handoff in handoffs.values {guard let release=releases[handoff.releaseID],handoff.resultLinks.allSatisfy({$0.evidence.allSatisfy(known)})else{throw invalid()};try handoff.validate(release:release)}
            for value in manifests.values {_ = try WorkPacketProjectionBuilderV1.rebuild(workspaceID:workspaceID,manifest:value,claims:Array(claims.values),leases:Array(leases.values),releases:Array(releases.values),handoffs:Array(handoffs.values),at:.distantFuture)}
        } catch {throw invalid()}
    }

    func validateFieldDrafts(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1
    ) throws {
        _ = members
        guard records.recordsSchemaVersion >= 15 else {
            guard records.fieldDrafts.isEmpty else { throw invalid() }
            return
        }
        guard (15...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              manifest.source.persistentSchemaVersion >= 16,
              let rawWorkspaceID = manifest.source.workspaceID else { throw invalid() }
        let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        var checkpoints: [UUID: FieldDraftCheckpointV1] = [:]
        var stages: [UUID: AttachmentStagingItemV1] = [:]
        var sagas: [UUID: DraftCommitSagaV1] = [:]
        var reservations: [UUID: DraftContentReservationV1] = [:]
        var commitReceipts: [UUID: DraftCommitReceiptV1] = [:]
        var discardReceipts: [UUID: DraftDiscardReceiptV1] = [:]
        for row in records.fieldDrafts {
            guard row.workspaceID == rawWorkspaceID else { throw invalid() }
            switch row.kind {
            case .checkpoint:
                let v = try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: row.canonicalData)
                guard v.workspaceID == workspaceID, v.draftID == row.id, v.draftRevision == row.revision,
                      checkpoints.updateValue(v, forKey: v.draftID) == nil else { throw invalid() }
            case .stagingItem:
                let v = try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: row.canonicalData)
                guard v.workspaceID == workspaceID, v.stageID == row.id, v.revision == row.revision,
                      stages.updateValue(v, forKey: v.stageID) == nil else { throw invalid() }
            case .commitSaga:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: row.canonicalData)
                guard v.workspaceID == workspaceID, v.sagaID == row.id, v.revision == row.revision,
                      sagas.updateValue(v, forKey: v.sagaID) == nil else { throw invalid() }
            case .contentReservation:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self, from: row.canonicalData)
                guard v.workspaceID == workspaceID, v.reservationID == row.id, v.revision == row.revision,
                      reservations.updateValue(v, forKey: v.reservationID) == nil else { throw invalid() }
            case .commitReceipt:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: row.canonicalData)
                guard v.workspaceID == workspaceID, v.receiptID == row.id, v.revision == row.revision,
                      commitReceipts.updateValue(v, forKey: v.receiptID) == nil else { throw invalid() }
            case .discardReceipt:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self, from: row.canonicalData)
                guard v.workspaceID == workspaceID, v.receiptID == row.id, v.revision == row.revision,
                      discardReceipts.updateValue(v, forKey: v.receiptID) == nil else { throw invalid() }
            }
        }
        for checkpoint in checkpoints.values {
            guard checkpoint.stageIDs.allSatisfy { stages[$0]?.draftID == checkpoint.draftID } else { throw invalid() }
        }
        for stage in stages.values {
            guard checkpoints[stage.draftID]?.stageIDs.contains(stage.stageID) == true else { throw invalid() }
        }
        for reservation in reservations.values {
            guard let stage = stages[reservation.stageID], stage.draftID == reservation.draftID,
                  checkpoints[reservation.draftID] != nil,
                  stage.contentDigest == reservation.contentDigest else { throw invalid() }
        }
        for saga in sagas.values {
            let availableDigests = Set(stages.values.filter { $0.draftID == saga.draftID }.compactMap { $0.contentDigest?.hexadecimalValue })
            guard checkpoints[saga.draftID] != nil,
                  Set(saga.plan.stageDigests).isSubset(of: availableDigests) else { throw invalid() }
            if let predecessorID = saga.predecessorSagaID {
                guard let predecessor = sagas[predecessorID] else { throw invalid() }
                try saga.validateSuccessor(of: predecessor)
            } else if saga.revision != 1 { throw invalid() }
        }
        var consumedSagaIDs = Set<UUID>()
        var committedReceiptDraftIDs = Set<UUID>()
        for receipt in commitReceipts.values {
            guard let saga = sagas[receipt.sagaID], saga.draftID == receipt.draftID,
                  saga.state == .draftRetired,
                  saga.plan.planSHA256 == receipt.commitPlanSHA256,
                  saga.plan.mutationID == receipt.targetMutationID,
                  let checkpoint = checkpoints[receipt.draftID],
                  checkpoint.state == .committed,
                  saga.mutationID == receipt.mutationID,
                  checkpoint.mutationID == receipt.mutationID,
                  checkpoint.lastDurableMutationID == receipt.mutationID,
                  checkpoint.lastReceiptSHA256 == receipt.receiptSHA256 else { throw invalid() }
            var chain: [DraftCommitSagaV1] = []
            var cursor: DraftCommitSagaV1? = saga
            var visited = Set<UUID>()
            while let value = cursor {
                guard visited.insert(value.sagaID).inserted else { throw invalid() }
                chain.append(value)
                cursor = try value.predecessorSagaID.map { predecessorID in
                    guard let predecessor = sagas[predecessorID] else { throw invalid() }
                    return predecessor
                }
            }
            let ordered = Array(chain.reversed())
            let expectedStates: [DraftCommitSagaStateV1] = [
                .prepared, .contentPromotedUnbound, .targetCommitted,
                .draftRetirePending, .draftRetired,
            ]
            let consumedReservations = reservations.values.filter {
                $0.workspaceID == saga.workspaceID
                    && $0.draftID == saga.draftID
                    && $0.commitPlanSHA256 == saga.plan.planSHA256
            }
            let consumed = Dictionary(uniqueKeysWithValues: consumedReservations.map {
                ($0.stageID.uuidString, $0.locator.contentID)
            })
            guard ordered.map(\.state) == expectedStates,
                  ordered.map(\.revision) == [1, 2, 3, 4, 5],
                  ordered.map(\.sagaSHA256) == receipt.sagaEventSHA256Chain,
                  consumedReservations.count == saga.plan.stageDigests.count,
                  Set(consumedReservations.map(\.stageID)).count == consumedReservations.count,
                  consumed == receipt.consumedStageToContentID else { throw invalid() }
            let chainIDs = Set(ordered.map(\.sagaID))
            guard consumedSagaIDs.isDisjoint(with: chainIDs),
                  committedReceiptDraftIDs.insert(receipt.draftID).inserted else {
                throw invalid()
            }
            consumedSagaIDs.formUnion(chainIDs)
        }
        guard consumedSagaIDs == Set(sagas.keys),
              Set(checkpoints.values.filter { $0.state == .committed }.map(\.draftID))
                == committedReceiptDraftIDs else { throw invalid() }
        for receipt in discardReceipts.values {
            guard checkpoints[receipt.draftID] != nil,
                  receipt.disposedStageIDs.allSatisfy { stages[$0]?.draftID == receipt.draftID },
                  receipt.quarantinedReservationIDs.allSatisfy { reservations[$0]?.draftID == receipt.draftID }
            else { throw invalid() }
        }
    }

    func validatePackageEvolution(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 16 else {
            guard records.packageEvolution.isEmpty else { throw invalid() }
            return
        }
        guard (16...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              (17...C52ServiceRequestBackupValidationBoundaryV1.persistentSchemaVersion)
                .contains(manifest.source.persistentSchemaVersion),
              let rawWorkspaceID = manifest.source.workspaceID else { throw invalid() }
        let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        var releases: [UUID: PromotedPackageReleaseV1] = [:]
        var runs: [UUID: PackageSandboxRunV1] = [:]
        var receipts: [UUID: PackagePromotionReceiptV1] = [:]
        var pointers: [UUID: ActivePackageRegistryPointerV1] = [:]
        do {
            for row in records.packageEvolution {
                guard row.workspaceID == rawWorkspaceID else { throw invalid() }
                switch row.kind {
                case .promotedRelease:
                    let value = try PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self, from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.releaseRecordID == row.id,
                          value.revision == row.revision,
                          releases.updateValue(value, forKey: value.releaseRecordID) == nil else { throw invalid() }
                case .sandboxRun:
                    let value = try PackageEvolutionCanonicalCodecV1.decode(PackageSandboxRunV1.self, from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.runID == row.id,
                          value.revision == row.revision,
                          runs.updateValue(value, forKey: value.runID) == nil else { throw invalid() }
                case .promotionReceipt:
                    let value = try PackageEvolutionCanonicalCodecV1.decode(PackagePromotionReceiptV1.self, from: row.canonicalData)
                    try value.validate()
                    guard value.workspaceID == workspaceID, value.receiptID == row.id,
                          value.revision == row.revision,
                          receipts.updateValue(value, forKey: value.receiptID) == nil else { throw invalid() }
                case .activePointer:
                    let value = try PackageEvolutionCanonicalCodecV1.decode(ActivePackageRegistryPointerV1.self, from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.pointerID == row.id,
                          value.revision == row.revision,
                          pointers.updateValue(value, forKey: value.pointerID) == nil else { throw invalid() }
                }
            }
            let closure = try PackageEvolutionLifecycleClosureV1(
                promotedReleases: Array(releases.values), sandboxRuns: Array(runs.values),
                promotionReceipts: Array(receipts.values), activePointers: Array(pointers.values)
            )
            try PackageEvolutionLifecycleAdapterV1.validateBackupRestore(closure)
            let actorDigests = try Set(records.partyAccountability.compactMap { row -> String? in
                guard row.kind == .actorSnapshot else { return nil }
                return try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: row.canonicalData).snapshotSHA256
            })
            guard receipts.values.allSatisfy({ actorDigests.contains($0.actorSnapshotSHA256) }) else { throw invalid() }
            for pointer in pointers.values {
                guard let release = releases[pointer.activeReleaseRecordID],
                      let receipt = receipts[pointer.promotionReceiptID],
                      pointer.activePackageReleaseID == release.packageRelease.packageReleaseID,
                      pointer.activeReleaseRecordSHA256 == release.releaseRecordSHA256,
                      receipt.resultingPointerSHA256 == pointer.pointerSHA256 else { throw invalid() }
                if let predecessorID = pointer.supersedesPointerID {
                    guard let predecessor = pointers[predecessorID],
                          receipt.predecessorPointerSHA256 == predecessor.pointerSHA256 else { throw invalid() }
                    try pointer.validateSuccessor(of: predecessor, expectedRevision: predecessor.revision)
                } else if receipt.predecessorPointerSHA256 != String(repeating: "0", count: 64) { throw invalid() }
            }
        } catch { throw invalid() }
    }

    func validateMeasurementIntegrity(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 17 else {
            guard records.measurementIntegrity.isEmpty else { throw invalid() }
            return
        }
        guard (17...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              (18...C52ServiceRequestBackupValidationBoundaryV1.persistentSchemaVersion)
                .contains(manifest.source.persistentSchemaVersion),
              let rawWorkspaceID = manifest.source.workspaceID else { throw invalid() }
        let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        var instruments:[UUID:InstrumentReferenceV1]=[:], calibrations:[UUID:CalibrationStatusSnapshotV1]=[:]
        var captures:[UUID:MeasurementCaptureV1]=[:], series:[UUID:MeasurementSeriesV1]=[:]
        var assessments:[UUID:MeasurementQualityAssessmentV1]=[:]
        do {
            for row in records.measurementIntegrity {
                guard row.workspaceID == rawWorkspaceID else { throw invalid() }
                switch row.kind {
                case .instrumentReference:
                    let v=try MeasurementIntegrityCanonicalCodecV1.decode(InstrumentReferenceV1.self,from:row.canonicalData)
                    guard v.workspaceID==workspaceID,v.referenceID==row.id,v.revision==row.revision,instruments.updateValue(v,forKey:v.referenceID)==nil else{throw invalid()}
                case .calibrationSnapshot:
                    let v=try MeasurementIntegrityCanonicalCodecV1.decode(CalibrationStatusSnapshotV1.self,from:row.canonicalData)
                    guard v.workspaceID==workspaceID,v.snapshotID==row.id,v.revision==row.revision,calibrations.updateValue(v,forKey:v.snapshotID)==nil else{throw invalid()}
                case .measurementCapture:
                    let v=try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementCaptureV1.self,from:row.canonicalData)
                    guard v.workspaceID==workspaceID,v.captureID==row.id,v.revision==row.revision,captures.updateValue(v,forKey:v.captureID)==nil else{throw invalid()}
                case .measurementSeries:
                    let v=try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementSeriesV1.self,from:row.canonicalData)
                    guard v.workspaceID==workspaceID,v.snapshotID==row.id,v.revision==row.revision,series.updateValue(v,forKey:v.snapshotID)==nil else{throw invalid()}
                case .qualityAssessment:
                    let v=try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementQualityAssessmentV1.self,from:row.canonicalData)
                    guard v.workspaceID==workspaceID,v.assessmentID==row.id,v.revision==row.revision,assessments.updateValue(v,forKey:v.assessmentID)==nil else{throw invalid()}
                }
            }
            for v in instruments.values { if let p=v.supersedesReferenceID { guard let predecessor=instruments[p] else{throw invalid()};try v.validateSuccessor(of:predecessor) } else if v.revision != 1 { throw invalid() } }
            for v in calibrations.values { guard let instrument=instruments[v.instrument.referenceID] else{throw invalid()};let reference=try InstrumentRevisionReferenceV1(instrument);guard reference==v.instrument else{throw invalid()};if let p=v.supersedesSnapshotID{guard let predecessor=calibrations[p] else{throw invalid()};try v.validateSuccessor(of:predecessor)}else if v.revision != 1{throw invalid()} }
            for v in captures.values { let instrument=try v.instrument.map{ ref in guard let x=instruments[ref.referenceID] else{throw invalid()};return x};let calibration=try v.calibration.map{ref in guard let x=calibrations[ref.snapshotID] else{throw invalid()};return x};try v.validateClosure(instrument:instrument,calibration:calibration);if let p=v.supersedesCaptureID{guard let predecessor=captures[p] else{throw invalid()};try v.validateSuccessor(of:predecessor)}else if v.revision != 1{throw invalid()} }
            let protocols = try records.authorityCriterion.filter{$0.kind == .measurementProtocolRelease}.map{try AuthorityCriterionCanonicalCodecV1.decode(MeasurementProtocolReleaseV1.self,from:$0.canonicalData)}
            var protocolsByID:[UUID:MeasurementProtocolReleaseV1]=[:]
            for value in protocols { guard protocolsByID.updateValue(value,forKey:value.releaseID)==nil else{throw invalid()} }
            for v in series.values { guard let protocolRelease=protocolsByID[v.protocolReference.releaseID] else{throw invalid()};try v.validateClosure(captures:Array(captures.values),protocolRelease:protocolRelease);if let p=v.supersedesSnapshotID{guard let predecessor=series[p] else{throw invalid()};try v.validateSuccessor(of:predecessor)}else if v.revision != 1{throw invalid()} }
            for v in assessments.values {
                switch v.subjectKind {
                case .capture:
                    guard let subject = captures[v.subjectID],
                          subject.revision == v.subjectRevision,
                          subject.captureSHA256 == v.subjectSHA256 else { throw invalid() }
                case .series:
                    let matchingSubjects = series.values.filter {
                        ($0.snapshotID == v.subjectID || $0.seriesID == v.subjectID)
                            && $0.revision == v.subjectRevision
                            && $0.seriesSHA256 == v.subjectSHA256
                    }
                    guard matchingSubjects.count == 1,
                          matchingSubjects[0].state == .finalized else { throw invalid() }
                }
                if let p = v.supersedesAssessmentID {
                    guard let predecessor = assessments[p] else { throw invalid() }
                    try v.validateSuccessor(of: predecessor)
                } else if v.revision != 1 {
                    throw invalid()
                }
            }
        } catch { throw invalid() }
    }

    func validatePrivacyTransforms(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 18 else {
            guard records.privacyTransforms.isEmpty else { throw invalid() }
            return
        }
        guard (records.recordsSchemaVersion == 18
                && manifest.source.persistentSchemaVersion == 19)
                || (records.recordsSchemaVersion == 19
                    && manifest.source.persistentSchemaVersion == 20)
                || (records.recordsSchemaVersion == 20
                    && manifest.source.persistentSchemaVersion == 21)
                || (records.recordsSchemaVersion == 21
                    && manifest.source.persistentSchemaVersion == 22)
                || (records.recordsSchemaVersion == 22
                    && manifest.source.persistentSchemaVersion == 23)
                || (records.recordsSchemaVersion == 23
                    && manifest.source.persistentSchemaVersion == 24)
                || (records.recordsSchemaVersion == 24
                    && manifest.source.persistentSchemaVersion == 25)
                || (records.recordsSchemaVersion == 25
                    && manifest.source.persistentSchemaVersion == 26)
                || (records.recordsSchemaVersion == 26
                    && manifest.source.persistentSchemaVersion == 27)
                || (records.recordsSchemaVersion == 27
                    && manifest.source.persistentSchemaVersion == 28)
                || (records.recordsSchemaVersion == 28
                    && manifest.source.persistentSchemaVersion == 29)
                || (records.recordsSchemaVersion == 29
                    && manifest.source.persistentSchemaVersion == 30)
                || (records.recordsSchemaVersion == 30
                    && manifest.source.persistentSchemaVersion == 31),
              let rawWorkspaceID = manifest.source.workspaceID else { throw invalid() }
        let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        var policies: [UUID: PrivacyTransformPolicyV1] = [:]
        var regions: [UUID: PrivacyRegionV1] = [:]
        var manifests: [UUID: PrivacyTransformManifestV1] = [:]
        var reviews: [UUID: PrivacyReviewReceiptV1] = [:]
        do {
            for row in records.privacyTransforms where row.kind == .policy || row.kind == .region {
                guard row.workspaceID == rawWorkspaceID else { throw invalid() }
                switch row.kind {
                case .policy:
                    let value = try PrivacyTransformCanonicalCodecV1.decodePolicy(from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.policyID == row.id,
                          value.revision == row.revision,
                          policies.updateValue(value, forKey: value.policyID) == nil else { throw invalid() }
                case .region:
                    let value = try PrivacyTransformCanonicalCodecV1.decodeRegion(from: row.canonicalData)
                    guard value.workspaceID == workspaceID, value.regionID == row.id,
                          value.revision == row.revision, value.revision == 1,
                          regions.updateValue(value, forKey: value.regionID) == nil else { throw invalid() }
                case .manifest, .reviewReceipt: throw invalid()
                }
            }
            for row in records.privacyTransforms where row.kind == .manifest {
                guard row.workspaceID == rawWorkspaceID else { throw invalid() }
                let reference = try JSONDecoder().decode(PrivacyTransformManifestDecodeEnvelopeV1.self, from: row.canonicalData)
                let policyMatches = policies.values.filter { $0.policyID == reference.policyID && $0.revision == reference.policyRevision && $0.policySHA256 == reference.policySHA256 }
                guard policyMatches.count == 1 else { throw invalid() }
                let provisional = try PrivacyTransformCanonicalCodecV1.decodeManifest(from: row.canonicalData, policy: policyMatches[0])
                let value = try PrivacyTransformManifestRow(provisional).value(policy: policyMatches[0])
                guard value.workspaceID == workspaceID, value.manifestID == row.id,
                      value.revision == row.revision,
                      manifests.updateValue(value, forKey: value.manifestID) == nil else { throw invalid() }
            }
            for row in records.privacyTransforms where row.kind == .reviewReceipt {
                guard row.workspaceID == rawWorkspaceID else { throw invalid() }
                let reference = try JSONDecoder().decode(PrivacyReviewDecodeEnvelopeV1.self, from: row.canonicalData)
                let manifestMatches = manifests.values.filter { $0.manifestID == reference.manifestID && $0.revision == reference.manifestRevision && $0.manifestSHA256 == reference.manifestSHA256 }
                let policyMatches = policies.values.filter { $0.policyID == reference.policyID && $0.revision == reference.policyRevision && $0.policySHA256 == reference.policySHA256 }
                guard manifestMatches.count == 1, policyMatches.count == 1 else { throw invalid() }
                let provisional = try PrivacyTransformCanonicalCodecV1.decodeReview(from: row.canonicalData, manifest: manifestMatches[0], policy: policyMatches[0])
                let value = try PrivacyReviewReceiptRow(provisional).value(manifest: manifestMatches[0], policy: policyMatches[0])
                guard value.workspaceID == workspaceID, value.receiptID == row.id,
                      value.revision == row.revision,
                      reviews.updateValue(value, forKey: value.receiptID) == nil else { throw invalid() }
            }
            for value in policies.values {
                if let predecessorID = value.supersedesPolicyID {
                    guard let predecessor = policies[predecessorID] else { throw invalid() }
                    try value.validateSuccessor(of: predecessor)
                } else if value.revision != 1 { throw invalid() }
            }
            var referencedRegionIDs = Set<UUID>()
            for value in manifests.values {
                let policyMatches = policies.values.filter {
                    $0.policyID == value.policyID && $0.revision == value.policyRevision
                        && $0.policySHA256 == value.policySHA256
                }
                guard policyMatches.count == 1 else { throw invalid() }
                let policy = policyMatches[0]
                func hasExactEvidence(_ reference: ContentReferenceV1) -> Bool {
                    guard let contentID = UUID(uuidString: reference.contentID) else { return false }
                    let matches = records.evidenceFiles.filter { $0.id == contentID }
                    guard matches.count == 1, let evidence = matches.first,
                          let digest = reference.digests.digest(for: .sha256) else { return false }
                    return evidence.sha256 == digest.hexadecimalValue
                        && Int64(evidence.byteCount) == reference.byteLength
                        && evidence.mimeType == reference.mediaType
                }
                guard hasExactEvidence(value.original), hasExactEvidence(value.derivative) else { throw invalid() }
                let exactRegions = try value.orderedRegions.map { embedded -> PrivacyRegionV1 in
                    guard let stored = regions[embedded.regionID], stored == embedded else { throw invalid() }
                    referencedRegionIDs.insert(stored.regionID)
                    return stored
                }
                try PrivacyTransformLifecycleClosureV1(
                    policy: policy, regions: exactRegions, manifest: value, review: nil
                ).validate()
                if let predecessorID = value.supersedesManifestID {
                    guard let predecessor = manifests[predecessorID] else { throw invalid() }
                    try value.validateSuccessor(of: predecessor, policy: policy)
                } else if value.revision != 1 { throw invalid() }
            }
            guard referencedRegionIDs == Set(regions.keys) else { throw invalid() }
            for value in reviews.values {
                let manifestMatches = manifests.values.filter {
                    $0.manifestID == value.manifestID && $0.revision == value.manifestRevision
                        && $0.manifestSHA256 == value.manifestSHA256
                }
                let policyMatches = policies.values.filter {
                    $0.policyID == value.policyID && $0.revision == value.policyRevision
                        && $0.policySHA256 == value.policySHA256
                }
                guard manifestMatches.count == 1, policyMatches.count == 1 else { throw invalid() }
                try PrivacyTransformLifecycleClosureV1(
                    policy: policyMatches[0], regions: manifestMatches[0].orderedRegions,
                    manifest: manifestMatches[0], review: value
                ).validate()
                if let predecessorID = value.supersedesReceiptID {
                    guard let predecessor = reviews[predecessorID] else { throw invalid() }
                    try value.validateSuccessor(
                        of: predecessor, manifest: manifestMatches[0], policy: policyMatches[0]
                    )
                } else if value.revision != 1 { throw invalid() }
            }
            try requireAcyclic(Array(policies.values), id: \.policyID, next: \.supersedesPolicyID)
            try requireAcyclic(Array(manifests.values), id: \.manifestID, next: \.supersedesManifestID)
            try requireAcyclic(Array(reviews.values), id: \.receiptID, next: \.supersedesReceiptID)
        } catch { throw invalid() }
    }

    func validateClientCapabilities(_ records:V4BackupRecordsV1,manifest:V4BackupManifestV1)throws{
        guard records.recordsSchemaVersion>=19 else{guard records.clientCapabilities.isEmpty else{throw invalid()};return}
        guard ((records.recordsSchemaVersion==19 && manifest.source.persistentSchemaVersion==20)||(records.recordsSchemaVersion==20 && manifest.source.persistentSchemaVersion==21)||(records.recordsSchemaVersion==21 && manifest.source.persistentSchemaVersion==22)||(records.recordsSchemaVersion==22 && manifest.source.persistentSchemaVersion==23)||(records.recordsSchemaVersion==23 && manifest.source.persistentSchemaVersion==24)||(records.recordsSchemaVersion==24 && manifest.source.persistentSchemaVersion==25)||(records.recordsSchemaVersion==25 && manifest.source.persistentSchemaVersion==26)||(records.recordsSchemaVersion==26 && manifest.source.persistentSchemaVersion==27)||(records.recordsSchemaVersion==27 && manifest.source.persistentSchemaVersion==28)||(records.recordsSchemaVersion==28 && manifest.source.persistentSchemaVersion==29)||(records.recordsSchemaVersion==29 && manifest.source.persistentSchemaVersion==30)||(records.recordsSchemaVersion==30 && manifest.source.persistentSchemaVersion==31)||(records.recordsSchemaVersion==31 && manifest.source.persistentSchemaVersion==32)||(records.recordsSchemaVersion==32 && manifest.source.persistentSchemaVersion==33)||(records.recordsSchemaVersion==33 && manifest.source.persistentSchemaVersion==34)),let rawWorkspaceID=manifest.source.workspaceID else{throw invalid()};let workspaceID=WorkspaceID(rawValue:rawWorkspaceID)
        do{
            let releases=try records.packageEvolution.filter{$0.kind == .promotedRelease}.map{try PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self,from:$0.canonicalData).packageRelease};let releaseIndex=Dictionary(uniqueKeysWithValues:releases.map{($0.packageReleaseID,$0)})
            var profiles:[UUID:ClientCapabilityProfileV1]=[:],policies:[UUID:PackageLifecyclePolicyV1]=[:],dispositions:[UUID:PackageLifecycleDispositionV1]=[:],decisions:[UUID:ClientCapabilityAdmissionDecisionV1]=[:]
            for row in records.clientCapabilities{guard row.workspaceID==rawWorkspaceID else{throw invalid()};switch row.kind{case .profile:let v=try ClientCapabilityProfileRow(ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityProfileV1.self,from:row.canonicalData)).value();guard v.workspaceID==workspaceID,v.profileID==row.id,v.revision==row.revision,profiles.updateValue(v,forKey:v.profileID)==nil else{throw invalid()};case .policy:let seed=try ClientCapabilityCanonicalCodecV1.decode(PackageLifecyclePolicyV1.self,from:row.canonicalData);guard let release=releaseIndex[seed.packageReleaseID]else{throw invalid()};let v=try PackageLifecyclePolicyRow(seed,release:release).value(release:release);guard v.workspaceID==workspaceID,v.policyID==row.id,v.revision==row.revision,policies.updateValue(v,forKey:v.policyID)==nil else{throw invalid()};case .disposition:let seed=try ClientCapabilityCanonicalCodecV1.decode(PackageLifecycleDispositionV1.self,from:row.canonicalData);guard let release=releaseIndex[seed.packageReleaseID]else{throw invalid()};let v=try PackageLifecycleDispositionRow(seed,release:release).value(release:release);guard v.workspaceID==workspaceID,v.dispositionID==row.id,v.revision==row.revision,dispositions.updateValue(v,forKey:v.dispositionID)==nil else{throw invalid()};case .admissionDecision:continue}}
            for row in records.clientCapabilities where row.kind == .admissionDecision{let seed=try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityAdmissionDecisionV1.self,from:row.canonicalData);guard let profile=profiles[seed.profileID],profile.revision==seed.profileRevision,profile.profileSHA256==seed.profileSHA256,let policy=policies[seed.policyID],policy.revision==seed.policyRevision,policy.policySHA256==seed.policySHA256,let disposition=dispositions[seed.dispositionID],disposition.revision==seed.dispositionRevision,disposition.dispositionSHA256==seed.dispositionSHA256,let release=releaseIndex[seed.packageReleaseID]else{throw invalid()};let v=try ClientCapabilityAdmissionDecisionRow(seed,profile:profile,policy:policy,disposition:disposition,release:release).value(profile:profile,policy:policy,disposition:disposition,release:release);try ClientCapabilityLifecycleClosureV1(profile:profile,policy:policy,disposition:disposition,decision:v,release:release).validate();guard v.workspaceID==workspaceID,v.decisionID==row.id,v.revision==row.revision,decisions.updateValue(v,forKey:v.decisionID)==nil else{throw invalid()}}
            for v in profiles.values{if let id=v.supersedesProfileID{guard let p=profiles[id]else{throw invalid()};try v.validateSuccessor(of:p)}else if v.revision != 1{throw invalid()}}
            for v in policies.values{guard let release=releaseIndex[v.packageReleaseID]else{throw invalid()};if let id=v.supersedesPolicyID{guard let p=policies[id]else{throw invalid()};try v.validateSuccessor(of:p,release:release)}else if v.revision != 1{throw invalid()}}
            for v in dispositions.values{guard let release=releaseIndex[v.packageReleaseID]else{throw invalid()};if let id=v.supersedesDispositionID{guard let p=dispositions[id]else{throw invalid()};try v.validateSuccessor(of:p,release:release)}else if v.revision != 1{throw invalid()}}
            try requireAcyclic(Array(profiles.values),id:\.profileID,next:\.supersedesProfileID);try requireAcyclic(Array(policies.values),id:\.policyID,next:\.supersedesPolicyID);try requireAcyclic(Array(dispositions.values),id:\.dispositionID,next:\.supersedesDispositionID)
        }catch{throw invalid()}
    }

    func validateRecoverabilityReceipts(_ records:V4BackupRecordsV1,manifest:V4BackupManifestV1)throws{
        guard records.recordsSchemaVersion>=20 else{guard records.recoverabilityReceipts.isEmpty else{throw invalid()};return}
        guard ((records.recordsSchemaVersion==20 && manifest.source.persistentSchemaVersion==21)||(records.recordsSchemaVersion==21 && manifest.source.persistentSchemaVersion==22)||(records.recordsSchemaVersion==22 && manifest.source.persistentSchemaVersion==23)||(records.recordsSchemaVersion==23 && manifest.source.persistentSchemaVersion==24)||(records.recordsSchemaVersion==24 && manifest.source.persistentSchemaVersion==25)||(records.recordsSchemaVersion==25 && manifest.source.persistentSchemaVersion==26)||(records.recordsSchemaVersion==26 && manifest.source.persistentSchemaVersion==27)||(records.recordsSchemaVersion==27 && manifest.source.persistentSchemaVersion==28)||(records.recordsSchemaVersion==28 && manifest.source.persistentSchemaVersion==29)||(records.recordsSchemaVersion==29 && manifest.source.persistentSchemaVersion==30)||(records.recordsSchemaVersion==30 && manifest.source.persistentSchemaVersion==31)||(records.recordsSchemaVersion==31 && manifest.source.persistentSchemaVersion==32)||(records.recordsSchemaVersion==32 && manifest.source.persistentSchemaVersion==33)||(records.recordsSchemaVersion==33 && manifest.source.persistentSchemaVersion==34)),let rawWorkspaceID=manifest.source.workspaceID else{throw invalid()}
        let workspaceID=WorkspaceID(rawValue:rawWorkspaceID)
        do{
            let decisions=try records.clientCapabilities.filter{$0.kind == .admissionDecision}.map{try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityAdmissionDecisionV1.self,from:$0.canonicalData)}
            let decisionIndex=Dictionary(uniqueKeysWithValues:decisions.map{($0.decisionID,$0)})
            var values:[UUID:RecoverabilityVerificationReceiptV1]=[:],successorCounts:[UUID:Int]=[:]
            for record in records.recoverabilityReceipts{
                let value=try RecoverabilityVerificationReceiptRow(RecoverabilityVerificationCanonicalCodecV1.decode(RecoverabilityVerificationReceiptV1.self,from:record.canonicalData)).value()
                guard value.workspaceID==workspaceID,value.receiptID==record.id,value.revision==record.revision,[(20,19),(21,20),(22,21)].contains(where:{$0.0==value.archive.persistentSchemaVersion && $0.1==value.archive.recordsSchemaVersion}),values.updateValue(value,forKey:value.receiptID)==nil else{throw invalid()}
                if value.archive.sourceWorkspaceID == workspaceID{guard let decision=decisionIndex[value.archive.clientCapability.decisionID],decision.revision==value.archive.clientCapability.decisionRevision,decision.decisionSHA256==value.archive.clientCapability.decisionSHA256 else{throw invalid()}}
            }
            for value in values.values{if let predecessorID=value.supersedesReceiptID{guard let predecessor=values[predecessorID]else{throw invalid()};try value.validateSuccessor(of:predecessor);successorCounts[predecessorID,default:0]+=1;guard successorCounts[predecessorID]==1 else{throw invalid()}}else if value.revision != 1{throw invalid()}}
            try requireAcyclic(Array(values.values),id:\.receiptID,next:\.supersedesReceiptID)
        }catch{throw invalid()}
    }
    func validateFieldReferences(_ records:V4BackupRecordsV1,manifest:V4BackupManifestV1)throws{
        guard records.recordsSchemaVersion>=21 else{guard records.fieldReferences.isEmpty else{throw invalid()};return}
        guard (21...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),manifest.source.persistentSchemaVersion==records.recordsSchemaVersion+1,let rawWorkspaceID=manifest.source.workspaceID else{throw invalid()}
        let workspaceID=WorkspaceID(rawValue:rawWorkspaceID)
        do{var releases:[UUID:FieldReferenceReleaseV1]=[:],bindings:[UUID:FieldReferenceBindingV1]=[:],releaseChildren:[UUID:Int]=[:],bindingChildren:[UUID:Int]=[:]
            for row in records.fieldReferences where row.kind == .release{let value=try FieldReferenceReleaseRow(FieldReferencePackCanonicalCodecV1.decode(FieldReferenceReleaseV1.self,from:row.canonicalData)).value();guard value.workspaceID==workspaceID,row.id==value.releaseID,row.workspaceID==rawWorkspaceID,row.revision==value.revision,releases.updateValue(value,forKey:value.releaseID)==nil else{throw invalid()}}
            for row in records.fieldReferences where row.kind == .binding{let seed=try FieldReferencePackCanonicalCodecV1.decode(FieldReferenceBindingV1.self,from:row.canonicalData);guard let release=releases[seed.releaseID]else{throw invalid()};let value=try FieldReferenceBindingRow(seed,release:release).value(release:release);guard value.workspaceID==workspaceID,row.id==value.bindingID,row.workspaceID==rawWorkspaceID,row.revision==value.revision,bindings.updateValue(value,forKey:value.bindingID)==nil else{throw invalid()}}
            for value in releases.values{if let id=value.supersedesReleaseID{guard let predecessor=releases[id]else{throw invalid()};try value.validateSuccessor(of:predecessor);releaseChildren[id,default:0]+=1;guard releaseChildren[id]==1 else{throw invalid()}}else if value.revision != 1{throw invalid()}}
            for value in bindings.values{if let id=value.supersedesBindingID{guard let predecessor=bindings[id],let release=releases[value.releaseID]else{throw invalid()};try value.validateSuccessor(of:predecessor,release:release);bindingChildren[id,default:0]+=1;guard bindingChildren[id]==1 else{throw invalid()}}else if value.revision != 1{throw invalid()}}
            try requireAcyclic(Array(releases.values),id:\.releaseID,next:\.supersedesReleaseID);try requireAcyclic(Array(bindings.values),id:\.bindingID,next:\.supersedesBindingID)
        }catch{throw invalid()}
    }

    func validateAccessibleDocumentAssessments(_ records:V4BackupRecordsV1,manifest:V4BackupManifestV1,members:ValidatedV4BackupMembersV1)throws{
        guard records.recordsSchemaVersion>=22 else{guard records.accessibleDocumentAssessments.isEmpty else{throw invalid()};return}
        guard (22...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),manifest.source.persistentSchemaVersion==records.recordsSchemaVersion+1,let workspaceID=manifest.source.workspaceID else{throw invalid()}
        do{var values:[UUID:AccessibleDocumentAssessmentReceiptV1]=[:],children:[UUID:Int]=[:]
            let evidenceLinks=try records.evidenceAssurance.filter{$0.kind == .evidenceLink}.map{try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self,from:$0.canonicalData)}
            let supersededLinkIDs=Set(evidenceLinks.compactMap(\.supersedesLinkID)),headEvidenceLinks=evidenceLinks.filter{!supersededLinkIDs.contains($0.linkID)}
            for record in records.accessibleDocumentAssessments{let value=try AccessibleDocumentCanonicalCodecV1.decode(AccessibleDocumentAssessmentReceiptV1.self,from:record.canonicalData);try value.validateIntrinsic();guard value.workspaceID.rawValue==workspaceID,record.id==value.receiptID,record.workspaceID==workspaceID,record.revision==value.revision,values.updateValue(value,forKey:value.receiptID)==nil else{throw invalid()};let boundPaths=records.reports.flatMap{report->[String] in var paths:[String]=[];if report.snapshotSHA256==value.outputSHA256{paths.append(report.snapshotRelativePath)};if report.pdfSHA256==value.outputSHA256,let path=report.pdfRelativePath{paths.append(path)};return paths};guard boundPaths.count==1,let output=members.descriptors[boundPaths[0]],output.sha256==value.outputSHA256,output.byteCount==value.outputByteCount else{throw invalid()};let evidenceAudience:EvidenceAudienceV1=value.audience == .customerSafe ? .customerReport:.internalReview
                for proof in value.externalProof{guard let evidenceID=UUID(uuidString:proof.evidenceID)else{throw invalid()};let owned=records.evidenceFiles.filter{$0.id==evidenceID};guard owned.count==1,let evidence=owned.first,records.workflowRecords.contains(where:{$0.id==evidence.recordID && $0.state==WorkflowState.completed.rawValue})else{throw invalid()};let candidates=[(V4BackupEvidenceMemberKeyV1.original(evidenceID),evidence.sha256,Int64(evidence.byteCount),evidence.mimeType),(V4BackupEvidenceMemberKeyV1.thumbnail(evidenceID),evidence.thumbnailSHA256,Int64(evidence.thumbnailByteCount),"image/jpeg")].filter{$0.1==proof.evidenceSHA256 && $0.3==proof.mediaType};guard candidates.count==1,let descriptor=members.descriptors[candidates[0].0],descriptor.sha256==proof.evidenceSHA256,descriptor.byteCount==candidates[0].2 else{throw invalid()};let visibilityMatches=headEvidenceLinks.filter{$0.workspaceID.rawValue==workspaceID && $0.evidenceID==proof.evidenceID && $0.evidenceSHA256==proof.evidenceSHA256 && $0.decision.audience==evidenceAudience};let authorities=Set(visibilityMatches.map{"\($0.visibilityID.uuidString)|\($0.visibilityRevision)|\($0.visibilitySHA256)|\($0.decision.disposition.rawValue)"});guard authorities.count==1,visibilityMatches.allSatisfy({$0.decision.disposition == .included}) else{throw invalid()}}
            }
            for value in values.values{if let id=value.supersedesReceiptID{guard let predecessor=values[id],predecessor.workspaceID==value.workspaceID,predecessor.treeSHA256==value.treeSHA256,predecessor.snapshotSHA256==value.snapshotSHA256,predecessor.manifestSHA256==value.manifestSHA256,predecessor.outputSHA256==value.outputSHA256,predecessor.revision<UInt64.max,value.revision==predecessor.revision+1 else{throw invalid()};children[id,default:0]+=1;guard children[id]==1 else{throw invalid()}}else if value.revision != 1{throw invalid()}}
            for start in values.keys{var seen=Set<UUID>(),cursor:UUID?=start;while let id=cursor{guard seen.insert(id).inserted else{throw invalid()};cursor=values[id]?.supersedesReceiptID}}
        }catch{throw invalid()}
    }

    /// Records 23 stores only the two canonical survey families. Lifecycle
    /// events remain journal post-images and are cross-checked here rather
    /// than being admitted as a third durable row family.
    func validateSurveyDefinitions(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 23 else {
            guard records.surveyDefinitions.isEmpty else { throw invalid() }
            return
        }
        guard (23...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              manifest.source.persistentSchemaVersion == records.recordsSchemaVersion+1,
              let rawWorkspaceID = manifest.source.workspaceID,
              let history = records.mutationHistory else { throw invalid() }
        let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        do {
            var identities: [UUID: SurveyDefinitionIdentityV1] = [:]
            var releases: [UUID: SurveyDefinitionReleaseV1] = [:]
            for record in records.surveyDefinitions {
                switch record.kind {
                case .identity:
                    let value = try SurveyDefinitionCanonicalCodecV1.decode(
                        SurveyDefinitionIdentityV1.self, from: record.canonicalData
                    )
                    guard value.workspaceID == workspaceID,
                          record.id == value.definitionID,
                          record.workspaceID == rawWorkspaceID,
                          record.revision == value.revision,
                          identities.updateValue(value, forKey: value.definitionID) == nil
                    else { throw invalid() }
                case .release:
                    let value = try SurveyDefinitionCanonicalCodecV1.decode(
                        SurveyDefinitionReleaseV1.self, from: record.canonicalData
                    )
                    try value.validate()
                    guard value.workspaceID == workspaceID,
                          record.id == value.releaseID,
                          record.workspaceID == rawWorkspaceID,
                          record.revision == value.revision,
                          releases.updateValue(value, forKey: value.releaseID) == nil
                    else { throw invalid() }
                }
            }
            try SurveyDefinitionBackupGraphClosureV1.validate(
                identities: Array(identities.values),
                releases: Array(releases.values),
                history: history,
                expectedWorkspaceID: workspaceID
            )
        } catch { throw invalid() }
    }

    func validateAssetLocators(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 25 else {
            guard records.assetLocators.isEmpty else { throw invalid() }
            return
        }
        guard (records.recordsSchemaVersion == 25 && manifest.source.persistentSchemaVersion == 26)
                || (records.recordsSchemaVersion == 26 && manifest.source.persistentSchemaVersion == 27)
                || (records.recordsSchemaVersion == 27 && manifest.source.persistentSchemaVersion == 28)
                || (records.recordsSchemaVersion == 28 && manifest.source.persistentSchemaVersion == 29)
                || (records.recordsSchemaVersion == 29 && manifest.source.persistentSchemaVersion == 30)
                || (records.recordsSchemaVersion == 30 && manifest.source.persistentSchemaVersion == 31)
                || (records.recordsSchemaVersion == 31 && manifest.source.persistentSchemaVersion == 32)
                || (records.recordsSchemaVersion == 32 && manifest.source.persistentSchemaVersion == 33)
                || (records.recordsSchemaVersion == 33 && manifest.source.persistentSchemaVersion == 34)
                || (records.recordsSchemaVersion == 34 && manifest.source.persistentSchemaVersion == 35)
                || (records.recordsSchemaVersion == 35 && manifest.source.persistentSchemaVersion == 36)
                || (records.recordsSchemaVersion == 36 && manifest.source.persistentSchemaVersion == 37) || (records.recordsSchemaVersion == 37 && manifest.source.persistentSchemaVersion == 38) || (records.recordsSchemaVersion == 38 && manifest.source.persistentSchemaVersion == 39) || (records.recordsSchemaVersion == 39 && manifest.source.persistentSchemaVersion == 40),
              let rawWorkspaceID = manifest.source.workspaceID,
              records.mutationHistory != nil else { throw invalid() }
        let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        do {
            var locators: [UUID: AssetLocatorV1] = [:]
            var receipts: [UUID: LocatorBindingReceiptV1] = [:]
            var keys = Set<String>()
            for row in records.assetLocators {
                guard row.workspaceID == rawWorkspaceID,
                      row.id != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)),
                      row.revision > 0,
                      keys.insert("\(row.kind.rawValue)|\(row.id.uuidString.lowercased())").inserted else {
                    throw invalid()
                }
                switch row.kind {
                case .locator:
                    let value = try AssetLocatorCanonicalCodecV1.decode(
                        AssetLocatorV1.self, from: row.canonicalData
                    )
                    try value.validate()
                    guard value.workspaceID == workspaceID,
                          value.locatorID == row.id,
                          value.revision == row.revision,
                          locators.updateValue(value, forKey: value.locatorID) == nil else {
                        throw invalid()
                    }
                case .bindingReceipt:
                    let value = try AssetLocatorCanonicalCodecV1.decode(
                        LocatorBindingReceiptV1.self, from: row.canonicalData
                    )
                    try value.validateIntrinsic()
                    guard value.workspaceID == workspaceID,
                          value.receiptID == row.id,
                          value.revision == row.revision,
                          receipts.updateValue(value, forKey: value.receiptID) == nil else {
                        throw invalid()
                    }
                }
            }
            guard records.assetLocators == records.assetLocators.sorted(by: {
                "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                    < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
            }) else { throw invalid() }
            try AssetLocatorLifecycleClosureV1(
                locators: Array(locators.values), receipts: Array(receipts.values)
            ).validate()
        } catch { throw invalid() }
    }

    func validateSchedules(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 26 else {
            guard records.schedules.isEmpty else { throw invalid() }
            return
        }
        guard (26...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              manifest.source.persistentSchemaVersion == records.recordsSchemaVersion + 1,
              let workspaceID = manifest.source.workspaceID,
              records.schedules.allSatisfy({ $0.workspaceID == workspaceID }),
              C51ScheduleBackupClosureV1.validatesEnvelope(records.schedules) else {
            throw invalid()
        }
        do {
            let encoded = try BackupCanonicalEncoderV1().encodeRecords(records).data
            _ = try BackupCanonicalDecoderV1().decodeRecords(encoded)
        } catch {
            throw invalid()
        }
    }

    func validatePlans(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 27 else {
            guard records.plans.isEmpty else { throw invalid() }
            return
        }
        guard (records.recordsSchemaVersion == 27 && manifest.source.persistentSchemaVersion == 28)
                || (records.recordsSchemaVersion == 28 && manifest.source.persistentSchemaVersion == 29)
                || (records.recordsSchemaVersion == 29 && manifest.source.persistentSchemaVersion == 30)
                || (records.recordsSchemaVersion == 30 && manifest.source.persistentSchemaVersion == 31)
                || (records.recordsSchemaVersion == 31 && manifest.source.persistentSchemaVersion == 32)
                || (records.recordsSchemaVersion == 32 && manifest.source.persistentSchemaVersion == 33)
                || (records.recordsSchemaVersion == 33 && manifest.source.persistentSchemaVersion == 34)
                || (records.recordsSchemaVersion == 34 && manifest.source.persistentSchemaVersion == 35)
                || (records.recordsSchemaVersion == 35 && manifest.source.persistentSchemaVersion == 36)
                || (records.recordsSchemaVersion == 36 && manifest.source.persistentSchemaVersion == 37) || (records.recordsSchemaVersion == 37 && manifest.source.persistentSchemaVersion == 38) || (records.recordsSchemaVersion == 38 && manifest.source.persistentSchemaVersion == 39) || (records.recordsSchemaVersion == 39 && manifest.source.persistentSchemaVersion == 40),
              let workspaceID = manifest.source.workspaceID,
              records.mutationHistory != nil,
              records.plans.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw invalid()
        }
        do {
            try V28PlanImportBoundaryV1.validate(persistent: 28, records: 27)
            _ = try PlanBackupRecordSetV1.decode(records.plans)
            let encoded = try BackupCanonicalEncoderV1().encodeRecords(records).data
            let decoded = try BackupCanonicalDecoderV1().decodeRecords(encoded)
            guard decoded.plans == records.plans else { throw invalid() }
        } catch {
            throw invalid()
        }
    }

    /// C37 admits only the durable pose event and spatial-anchor observation
    /// rows. Current tips, completed placement snapshots, and editor state are
    /// derived and are intentionally absent from the archive graph. The
    /// closure validator also binds every row to the package workspace and
    /// rejects gaps, forks, cross-axis/cross-asset predecessors, and frame
    /// or placement-episode drift in an observation chain.
    func validatePlacementPoses(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 28 else {
            guard records.placementPoses.isEmpty else { throw invalid() }
            return
        }
        guard (records.recordsSchemaVersion == 28 && manifest.source.persistentSchemaVersion == 29)
                || (records.recordsSchemaVersion == 29 && manifest.source.persistentSchemaVersion == 30)
                || (records.recordsSchemaVersion == 30 && manifest.source.persistentSchemaVersion == 31)
                || (records.recordsSchemaVersion == 31 && manifest.source.persistentSchemaVersion == 32)
                || (records.recordsSchemaVersion == 32 && manifest.source.persistentSchemaVersion == 33)
                || (records.recordsSchemaVersion == 33 && manifest.source.persistentSchemaVersion == 34)
                || (records.recordsSchemaVersion == 34 && manifest.source.persistentSchemaVersion == 35)
                || (records.recordsSchemaVersion == 35 && manifest.source.persistentSchemaVersion == 36)
                || (records.recordsSchemaVersion == 36 && manifest.source.persistentSchemaVersion == 37) || (records.recordsSchemaVersion == 37 && manifest.source.persistentSchemaVersion == 38) || (records.recordsSchemaVersion == 38 && manifest.source.persistentSchemaVersion == 39) || (records.recordsSchemaVersion == 39 && manifest.source.persistentSchemaVersion == 40),
              let workspaceID = manifest.source.workspaceID,
              records.mutationHistory != nil,
              records.placementPoses.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw invalid()
        }
        do {
            try V29PlacementPoseImportBoundaryV1.validate(persistent: 29, records: 28)
            let decoded = try PlacementPoseBackupRecordSetV1.decode(records.placementPoses)
            guard decoded.poseEvents.allSatisfy({ $0.workspaceID.rawValue == workspaceID }) else {
                throw invalid()
            }
            guard decoded.spatialAnchors.allSatisfy({ $0.workspaceID.rawValue == workspaceID }) else {
                throw invalid()
            }
            let encoded = try BackupCanonicalEncoderV1().encodeRecords(records).data
            let roundTrip = try BackupCanonicalDecoderV1().decodeRecords(encoded)
            guard roundTrip.placementPoses == records.placementPoses else { throw invalid() }
        } catch {
            throw invalid()
        }
    }

    func validateLighting(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= 30 else {
            guard records.lighting.isEmpty else { throw invalid() }
            return
        }
        guard ((records.recordsSchemaVersion == 30 && manifest.source.persistentSchemaVersion == 31)
                || (records.recordsSchemaVersion == 31 && manifest.source.persistentSchemaVersion == 32)
                || (records.recordsSchemaVersion == 32 && manifest.source.persistentSchemaVersion == 33)
                || (records.recordsSchemaVersion == 33 && manifest.source.persistentSchemaVersion == 34)
                || (records.recordsSchemaVersion == 34 && manifest.source.persistentSchemaVersion == 35)
                || (records.recordsSchemaVersion == 35 && manifest.source.persistentSchemaVersion == 36)
                || (records.recordsSchemaVersion == 36 && manifest.source.persistentSchemaVersion == 37) || (records.recordsSchemaVersion == 37 && manifest.source.persistentSchemaVersion == 38) || (records.recordsSchemaVersion == 38 && manifest.source.persistentSchemaVersion == 39) || (records.recordsSchemaVersion == 39 && manifest.source.persistentSchemaVersion == 40)),
              let workspaceID = manifest.source.workspaceID,
              records.mutationHistory != nil,
              records.lighting.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw invalid()
        }
        do {
            try C31LightingPackageValidationV1.validate(records)
            let encoded = try BackupCanonicalEncoderV1().encodeRecords(records).data
            let roundTrip = try BackupCanonicalDecoderV1().decodeRecords(encoded)
            guard roundTrip.lighting == records.lighting else { throw invalid() }
        } catch {
            throw invalid()
        }
    }

    func validateGuidedSurveys(_ records:V4BackupRecordsV1,manifest:V4BackupManifestV1)throws{
        guard records.recordsSchemaVersion>=24 else{guard records.guidedSurveys.isEmpty else{throw invalid()};return}
        guard (24...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),manifest.source.persistentSchemaVersion==records.recordsSchemaVersion+1,let workspaceID=manifest.source.workspaceID,records.mutationHistory != nil else{throw invalid()}
        do{
            guard records.guidedSurveys.allSatisfy({$0.workspaceID==workspaceID})else{throw invalid()}
            let bytes=try BackupCanonicalEncoderV1().encodeRecords(records).data
            let decoded=try BackupCanonicalDecoderV1().decodeRecords(bytes)
            guard decoded.guidedSurveys==records.guidedSurveys else{throw invalid()}
        }catch{throw invalid()}
    }

    func validateInspectionReview(
        _ records: V4BackupRecordsV1, manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1
    ) throws {
        guard records.recordsSchemaVersion >= 13 else {
            guard records.inspectionReview.isEmpty else { throw invalid() }
            return
        }
        guard (13...C53ServiceReliabilityBackupPackageValidationV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              (manifest.source.persistentSchemaVersion == 14 || manifest.source.persistentSchemaVersion == 15
                || manifest.source.persistentSchemaVersion == 16
                || manifest.source.persistentSchemaVersion == 17
                || manifest.source.persistentSchemaVersion == 18
                || manifest.source.persistentSchemaVersion == 19
                || manifest.source.persistentSchemaVersion == 20
                || manifest.source.persistentSchemaVersion == 21 || manifest.source.persistentSchemaVersion == 22 || manifest.source.persistentSchemaVersion == 23 || manifest.source.persistentSchemaVersion == 24 || manifest.source.persistentSchemaVersion == 25 || manifest.source.persistentSchemaVersion == 26 || manifest.source.persistentSchemaVersion == 27 || manifest.source.persistentSchemaVersion == 28 || manifest.source.persistentSchemaVersion == 29),
              records.inspectionReview.count <= InspectionReviewLimitsV1.maximumHistory,
              let rawWorkspaceID = manifest.source.workspaceID else { throw invalid() }
        do {
            let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
            var transitions: [UUID: InspectionReviewTransitionV1] = [:]
            var dispositions: [UUID: ReviewDispositionV1] = [:]
            var requests: [UUID: ChangeRequestV1] = [:]
            var policies: [UUID: CorrectiveActionPolicyV1] = [:]
            var actions: [UUID: CorrectiveActionEventV1] = [:]
            var actorSnapshots: [UUID: ActorSnapshotV1] = [:]
            var partyIDs = Set<UUID>()
            var assuranceManifests: [UUID: AssuranceManifestV1] = [:]
            var evidenceLinks: [UUID: ClaimEvidenceLinkV1] = [:]
            var exactReferences: [String: Set<String>] = [:]
            func normalizedReferenceID(_ id: String) -> String {
                UUID(uuidString: id)?.uuidString ?? id
            }
            func addReference(_ family: String, _ id: String, _ revision: UInt64, _ digest: String) {
                exactReferences["\(family)\u{0}\(normalizedReferenceID(id))", default: []].insert("\(revision)\u{0}\(digest)")
            }
            func hasReference(_ family: String, _ id: String, _ revision: UInt64, _ digest: String) -> Bool {
                exactReferences["\(family)\u{0}\(normalizedReferenceID(id))"]?.contains("\(revision)\u{0}\(digest)") == true
            }
            for row in records.partyAccountability {
                switch row.kind {
                case .serviceParty:
                    let party = try PartyAccountabilitySnapshotCodecV1.decode(ServicePartyReferenceV1.self, from: row.canonicalData)
                    partyIDs.insert(party.partyID)
                case .actorSnapshot:
                    let actor = try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: row.canonicalData)
                    actorSnapshots[actor.snapshotID] = actor
                case .sitePartyRoleEvent, .qualificationSnapshot, .signoffSnapshot: break
                }
            }
            for row in records.evidenceAssurance where row.kind == .manifest {
                let manifest = try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: row.canonicalData)
                assuranceManifests[manifest.manifestID] = manifest
            }
            for row in records.evidenceAssurance where row.kind == .evidenceLink {
                let link = try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: row.canonicalData)
                evidenceLinks[link.linkID] = link
                addReference("evidence", link.linkID.uuidString, link.revision, link.linkSHA256)
                addReference("claimEvidenceLink", link.linkID.uuidString, link.revision, link.linkSHA256)
            }
            for report in records.reports {
                guard let bytes = members[report.snapshotRelativePath] else { throw invalid() }
                if report.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion {
                    let snapshot = try CompletedActivitySnapshotCanonicalCodecV2.decode(bytes)
                    guard let reportRevision = UInt64(exactly: report.snapshotSchemaVersion) else {
                        throw invalid()
                    }
                    for id in [report.id.uuidString, snapshot.payload.activity.reportID,
                               snapshot.payload.activity.snapshotID,
                               snapshot.payload.activity.sourceActivityID] {
                        addReference("reportSnapshot", id, reportRevision, report.snapshotSHA256)
                        addReference("completedActivitySnapshot", id, reportRevision, report.snapshotSHA256)
                    }
                    continue
                }
                let snapshot = try ReportSnapshotEncoderV1().decode(bytes)
                guard let reportRevision = UInt64(exactly: report.snapshotSchemaVersion) else { throw invalid() }
                for id in [report.id.uuidString, snapshot.reportID.uuidString,
                           snapshot.sourceRecordID.uuidString, snapshot.stableRootID.uuidString] {
                    addReference("reportSnapshot", id, reportRevision, report.snapshotSHA256)
                    addReference("completedActivitySnapshot", id, reportRevision, report.snapshotSHA256)
                }
                if let relationship = snapshot.functionalRelationships {
                    guard let relationshipRevision = UInt64(exactly: relationship.schemaVersion) else { throw invalid() }
                    addReference("functionalRelationshipSnapshot", relationship.snapshotID.uuidString,
                                 relationshipRevision, relationship.snapshotSHA256)
                }
                for evaluation in snapshot.requirementAssurance?.evaluations ?? [] {
                    addReference("requirementEvaluation", evaluation.requirementID,
                                 evaluation.evaluatedRevision,
                                 try WorkspaceMutationCanonicalV1.sha256(evaluation))
                }
            }
            for record in records.functionalRelationships where record.kind == .event {
                let value = try FunctionalRelationshipCanonicalCodecV1.decode(AssetFunctionalRelationshipEventV1.self, from: record.canonicalData)
                addReference("functionalRelationship", value.relationshipID.uuidString, value.revision, value.eventSHA256)
                addReference("functionalRelationship", value.eventID.uuidString, value.revision, value.eventSHA256)
            }
            for record in records.authorityCriterion where record.kind == .findingClassificationBinding {
                let value = try AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: record.canonicalData)
                addReference("finding", value.findingID.uuidString, value.revision, value.bindingSHA256)
                addReference("criterion", value.criterionID, value.revision, value.bindingSHA256)
            }
            for evidence in records.evidenceFiles {
                addReference("externalEvidenceReference", evidence.id.uuidString, 1, evidence.sha256)
            }
            for row in records.inspectionReview {
                switch row.kind {
                case .reviewTransition:
                    let value = try InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self, from: row.canonicalData)
                    guard value.transitionID == row.id, value.workspaceID == workspaceID, value.revision == row.revision,
                          transitions.updateValue(value, forKey: value.transitionID) == nil else { throw invalid() }
                case .reviewDisposition:
                    let value = try InspectionReviewCanonicalCodecV1.decode(ReviewDispositionV1.self, from: row.canonicalData)
                    guard value.dispositionID == row.id, value.workspaceID == workspaceID, value.revision == row.revision,
                          dispositions.updateValue(value, forKey: value.dispositionID) == nil else { throw invalid() }
                case .changeRequest:
                    let value = try InspectionReviewCanonicalCodecV1.decode(ChangeRequestV1.self, from: row.canonicalData)
                    guard value.requestRevisionID == row.id, value.workspaceID == workspaceID, value.revision == row.revision,
                          requests.updateValue(value, forKey: value.requestRevisionID) == nil else { throw invalid() }
                case .correctiveActionPolicy:
                    let value = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self, from: row.canonicalData)
                    guard value.releaseID == row.id, value.workspaceID == workspaceID, value.revision == row.revision,
                          policies.updateValue(value, forKey: value.releaseID) == nil else { throw invalid() }
                case .correctiveActionEvent:
                    let value = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionEventV1.self, from: row.canonicalData)
                    guard value.eventID == row.id, value.workspaceID == workspaceID, value.revision == row.revision,
                          actions.updateValue(value, forKey: value.eventID) == nil else { throw invalid() }
                }
            }
            try validateInspectionReviewChains(transitions, dispositions, requests, policies, actions)
            for value in transitions.values {
                addReference("review", value.reviewID.uuidString, value.revision, value.transitionSHA256)
            }
            let requestsByStableID = Dictionary(grouping: requests.values, by: \.requestID)
            func known(_ actor: ActorSnapshotV1) -> Bool {
                actorSnapshots[actor.snapshotID] == actor
                    && (actor.actor.partyID.map(partyIDs.contains) ?? true)
            }
            func known(_ evidence: [ReviewEvidenceReferenceV1]) -> Bool {
                evidence.allSatisfy { value in
                    let family: String
                    switch value.kind {
                    case .claimEvidenceLink: family = "claimEvidenceLink"
                    case .verifiedRecheck: family = "verifiedRecheck"
                    case .completedActivitySnapshot: family = "completedActivitySnapshot"
                    case .requirementEvaluation: family = "requirementEvaluation"
                    case .functionalRelationshipSnapshot: family = "functionalRelationshipSnapshot"
                    case .externalEvidenceReference: family = "externalEvidenceReference"
                    }
                    return hasReference(family, value.referenceID, value.revision, value.sha256)
                }
            }
            func known(_ subject: InspectionReviewSubjectReferenceV1) -> Bool {
                let family: String
                switch subject.kind {
                case .completedActivitySnapshot: family = "completedActivitySnapshot"
                case .reportSnapshot: family = "reportSnapshot"
                case .finding: family = "finding"
                }
                return hasReference(family, subject.subjectID, subject.subjectRevision, subject.subjectSHA256)
            }
            func known(_ item: ChangeRequestItemReferenceV1) -> Bool {
                let family: String
                switch item.kind {
                case .review: family = "review"
                case .finding: family = "finding"
                case .criterion: family = "criterion"
                case .evidence: family = "evidence"
                case .functionalRelationship: family = "functionalRelationship"
                }
                return hasReference(family, item.itemID, item.itemRevision, item.itemSHA256)
            }
            guard transitions.values.allSatisfy({ value in
                (value.dispositionID.map { id in
                    dispositions[id].map {
                        (value.toState == .accepted || value.toState == .changesRequested)
                            && $0.reviewID == value.reviewID && $0.subject == value.subject
                            && $0.reviewRevision == value.revision && $0.mutationID == value.mutationID
                            && $0.changeRequestIDs == value.changeRequestIDs
                            && $0.kind == (value.toState == .accepted ? .accepted : .changesRequested)
                    } ?? false
                } ?? true)
                    && value.changeRequestIDs.allSatisfy { id in
                        requestsByStableID[id]?.filter {
                            $0.reviewID == value.reviewID && $0.reviewRevision == value.revision
                                && $0.mutationID == value.mutationID
                        }.count == 1
                    } && known(value.actor) && known(value.subject)
            }), dispositions.values.allSatisfy({ value in
                transitions.values.filter {
                    $0.dispositionID == value.dispositionID && $0.reviewID == value.reviewID
                        && $0.revision == value.reviewRevision && $0.mutationID == value.mutationID
                }.count == 1 && value.changeRequestIDs.allSatisfy { id in
                    requestsByStableID[id]?.contains {
                        $0.reviewID == value.reviewID && $0.reviewRevision == value.reviewRevision
                            && $0.mutationID == value.mutationID
                    } == true
                } && known(value.reviewer)
                    && (value.assuranceManifestID.map { id in
                        assuranceManifests[id].map { manifest in
                            guard let revision = value.assuranceManifestRevision,
                                  let digest = value.assuranceManifestSHA256 else { return false }
                            return manifest.revision == revision && manifest.manifestSHA256 == digest
                        } ?? false
                    } ?? true)
            }), requests.values.allSatisfy({ value in
                transitions.values.filter {
                    $0.reviewID == value.reviewID && $0.revision == value.reviewRevision
                        && $0.mutationID == value.mutationID
                        && $0.changeRequestIDs.contains(value.requestID)
                }.count == 1 && known(value.item) && known(value.requester) && (value.resolution.map {
                    known($0.resolver) && known($0.evidence)
                } ?? true)
            }), actions.values.allSatisfy({ value in
                (policies[value.policy.releaseID].map {
                    $0.policyID == value.policy.policyID && $0.revision == value.policy.revision
                        && $0.policySHA256 == value.policy.sha256
                } ?? false)
                    && known(value.recorder) && (value.verifier.map(known) ?? true)
                    && known(value.closureEvidence)
                    && known(value.source)
                    && (value.assignee?.partyID.map(partyIDs.contains) ?? true)
            }) else { throw invalid() }
        } catch { throw invalid() }
    }

    func validateInspectionReviewChains(
        _ transitions: [UUID: InspectionReviewTransitionV1],
        _ dispositions: [UUID: ReviewDispositionV1], _ requests: [UUID: ChangeRequestV1],
        _ policies: [UUID: CorrectiveActionPolicyV1], _ actions: [UUID: CorrectiveActionEventV1]
    ) throws {
        let transitionRoots = transitions.values.filter { $0.predecessorTransitionID == nil }
        let dispositionRoots = dispositions.values.filter { $0.supersedesDispositionID == nil }
        let requestRoots = requests.values.filter { $0.supersedesRequestRevisionID == nil }
        let policyRoots = policies.values.filter { $0.supersedesReleaseID == nil }
        let actionRoots = actions.values.filter { $0.predecessorEventID == nil }
        guard Set(transitionRoots.map(\.reviewID)).count == transitionRoots.count,
              Set(dispositionRoots.map(\.reviewID)).count == dispositionRoots.count,
              Set(requestRoots.map(\.requestID)).count == requestRoots.count,
              Set(policyRoots.map(\.policyID)).count == policyRoots.count,
              Set(actionRoots.map(\.actionID)).count == actionRoots.count else { throw invalid() }
        for value in actionRoots {
            guard let policy = policies[value.policy.releaseID] else { throw invalid() }
            try value.validateAdmission(policy: policy)
        }
        var claimed = Set<UUID>()
        for value in transitions.values {
            if let id = value.predecessorTransitionID {
                guard let predecessor = transitions[id], claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor)
            }
        }
        try requireAcyclic(Array(transitions.values), id: \.transitionID, next: \.predecessorTransitionID)
        claimed.removeAll()
        for value in dispositions.values {
            if let id = value.supersedesDispositionID {
                guard let predecessor = dispositions[id], claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor)
            }
        }
        try requireAcyclic(Array(dispositions.values), id: \.dispositionID, next: \.supersedesDispositionID)
        claimed.removeAll()
        for value in requests.values {
            if let id = value.supersedesRequestRevisionID {
                guard let predecessor = requests[id], claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor)
            }
        }
        try requireAcyclic(Array(requests.values), id: \.requestRevisionID, next: \.supersedesRequestRevisionID)
        claimed.removeAll()
        for value in policies.values {
            if let id = value.supersedesReleaseID {
                guard let predecessor = policies[id], claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor)
            }
        }
        try requireAcyclic(Array(policies.values), id: \.releaseID, next: \.supersedesReleaseID)
        claimed.removeAll()
        for value in actions.values {
            if let id = value.predecessorEventID {
                guard let predecessor = actions[id], let policy = policies[value.policy.releaseID],
                      claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor, policy: policy)
            }
        }
        try requireAcyclic(Array(actions.values), id: \.eventID, next: \.predecessorEventID)
    }

    func validateEvidenceAssuranceChains(
        _ visibilities: [UUID: EvidenceVisibilityV1],
        _ links: [UUID: ClaimEvidenceLinkV1],
        _ manifests: [UUID: AssuranceManifestV1],
        _ attestations: [UUID: AttestationV1]
    ) throws {
        var claimed = Set<UUID>()
        for value in visibilities.values {
            if let id = value.supersedesVisibilityID {
                guard let predecessor = visibilities[id], claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor)
            }
        }
        try requireAcyclic(Array(visibilities.values), id: \.visibilityID, next: \.supersedesVisibilityID)
        claimed.removeAll()
        for value in links.values {
            if let id = value.supersedesLinkID {
                guard let predecessor = links[id], let visibility = visibilities[value.visibilityID],
                      claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor, visibility: visibility)
            }
        }
        try requireAcyclic(Array(links.values), id: \.linkID, next: \.supersedesLinkID)
        claimed.removeAll()
        for value in manifests.values {
            if let id = value.supersedesManifestID {
                guard let predecessor = manifests[id], claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor)
            }
        }
        try requireAcyclic(Array(manifests.values), id: \.manifestID, next: \.supersedesManifestID)
        claimed.removeAll()
        for value in attestations.values {
            if let id = value.supersedesAttestationID {
                guard let predecessor = attestations[id], claimed.insert(id).inserted else { throw invalid() }
                try value.validateSuccessor(of: predecessor)
            }
        }
        try requireAcyclic(Array(attestations.values), id: \.attestationID, next: \.supersedesAttestationID)
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
                    && manifest.source.persistentSchemaVersion == 7)
                || (records.recordsSchemaVersion == 7
                    && manifest.source.persistentSchemaVersion == 8)
                || (records.recordsSchemaVersion == 8
                    && manifest.source.persistentSchemaVersion == 9)
                || (records.recordsSchemaVersion == 9
                    && manifest.source.persistentSchemaVersion == 10)
                || (records.recordsSchemaVersion == 10
                    && manifest.source.persistentSchemaVersion == 11)
                || (records.recordsSchemaVersion == 11
                    && manifest.source.persistentSchemaVersion == 12)
                || (records.recordsSchemaVersion == 12
                    && manifest.source.persistentSchemaVersion == 13)
                || (records.recordsSchemaVersion == 13
                    && manifest.source.persistentSchemaVersion == 14)
                || (records.recordsSchemaVersion == 14
                    && manifest.source.persistentSchemaVersion == 15)
                || (records.recordsSchemaVersion == 15
                    && manifest.source.persistentSchemaVersion == 16)
                || (records.recordsSchemaVersion == 16
                    && manifest.source.persistentSchemaVersion == 17)
                || (records.recordsSchemaVersion == 17
                    && manifest.source.persistentSchemaVersion == 18)
                || (records.recordsSchemaVersion == 18
                    && manifest.source.persistentSchemaVersion == 19)
                || (records.recordsSchemaVersion == 19
                    && manifest.source.persistentSchemaVersion == 20)
                || (records.recordsSchemaVersion == 20
                    && manifest.source.persistentSchemaVersion == 21)
                || (records.recordsSchemaVersion == 21
                    && manifest.source.persistentSchemaVersion == 22)
                || (records.recordsSchemaVersion == 22
                    && manifest.source.persistentSchemaVersion == 23)
                || (records.recordsSchemaVersion == 23
                    && manifest.source.persistentSchemaVersion == 24)
                || (records.recordsSchemaVersion == 24
                    && manifest.source.persistentSchemaVersion == 25)
                || (records.recordsSchemaVersion == 25
                    && manifest.source.persistentSchemaVersion == 26)
                || (records.recordsSchemaVersion == 26
                    && manifest.source.persistentSchemaVersion == 27)
                || (records.recordsSchemaVersion == 27
                    && manifest.source.persistentSchemaVersion == 28)
                || (records.recordsSchemaVersion == 28
                    && manifest.source.persistentSchemaVersion == 29)
                || (records.recordsSchemaVersion == 29
                    && manifest.source.persistentSchemaVersion == 30)
                || (records.recordsSchemaVersion == 30
                    && manifest.source.persistentSchemaVersion == 31)),
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
             (5, let value?, let history?), (6, let value?, let history?),
             (7, let value?, let history?), (8, let value?, let history?),
             (9, let value?, let history?):
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
        if members.descriptors[PortableExchangeBackupMemberV2.path] != nil {
            _ = try C48PortableExchangeBackupPackageValidationV2.snapshot(
                manifest: manifest,
                members: members
            )
            expected.insert(PortableExchangeBackupMemberV2.path)
        }
        let normalizer = MediaNormalizerV1()
        for evidence in records.evidenceFiles {
            try cancellation.checkpoint()
            let id = uuid(evidence.id)
            let originalPath = V4BackupEvidenceMemberKeyV1.original(evidence.id)
            let thumbnailPath = V4BackupEvidenceMemberKeyV1.thumbnail(evidence.id)
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
        for record in records.fieldDrafts where record.kind == .stagingItem {
            let item = try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self,from:record.canonicalData)
            guard let byteCount=item.actualByteCount else { continue }
            let path="draft-staging/\(uuid(item.draftID))/\(uuid(item.stageID)).bin"
            let expectedSHA=item.contentReference?.digests.digest(for:.sha256)?.hexadecimalValue
                ?? (item.contentDigest?.algorithm == .sha256 ? item.contentDigest?.hexadecimalValue:nil)
            guard let bytes=members[path],bytes.count==Int(byteCount),let expectedSHA,
                  CanonicalJSONV1.sha256(bytes)==expectedSHA else{throw invalid()}
            expected.insert(path)
        }
        guard members.keys == expected,
              Set(manifest.entries.map(\.path)) == expected.subtracting(["manifest.json"]) else {
            throw invalid()
        }
    }
}

enum C48PortableExchangeBackupPackageValidationV2 {
    static func snapshot(
        manifest: V4BackupManifestV1,
        members: ValidatedV4BackupMembersV1
    ) throws -> PortableExchangeBackupSnapshotV2? {
        guard let descriptor = members.descriptors[PortableExchangeBackupMemberV2.path] else {
            return nil // Released pre-C48 V4 packages carry no session staging member.
        }
        guard descriptor.byteCount > 0,
              descriptor.byteCount <= Int64(PortableExchangeBackupMemberV2.maximumByteCount),
              manifest.entries.contains(where: {
                  $0.path == PortableExchangeBackupMemberV2.path
                      && $0.mimeType == PortableExchangeBackupMemberV2.mimeType
                      && Int64($0.byteCount) == descriptor.byteCount
                      && $0.sha256 == descriptor.sha256
              }),
              let bytes = members[PortableExchangeBackupMemberV2.path] else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        let snapshot: PortableExchangeBackupSnapshotV2
        do {
            snapshot = try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
                PortableExchangeBackupSnapshotV2.self,
                from: bytes,
                validate: { try $0.validate() }
            )
        } catch {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        let payloadKeys = snapshot.immutablePayloads.map {
            "\($0.role.rawValue):\($0.sha256)"
        }
        let referencedPayloadKeys = snapshot.sessions.flatMap { session in
            session.immutableBytes.map { "\($0.role.rawValue):\($0.sha256)" }
        }
        let capabilitySessionIDs = snapshot.protectedCapabilityArtifacts.map(\.sessionID)
        let activeSessionIDs = snapshot.sessions.filter {
            $0.capabilityState.isActive
        }.map(\.sessionID)
        let orderedSessions = snapshot.sessions.sorted {
            ($0.namespace.rawValue, $0.publicRequestID, $0.revision)
                < ($1.namespace.rawValue, $1.publicRequestID, $1.revision)
        }
        guard snapshot.sessions == orderedSessions,
              snapshot.sessions.allSatisfy({ session in
                  session.workspaceID == nil
                      || session.workspaceID == manifest.source.workspaceID
              }),
              snapshot.sessions.allSatisfy({ session in
                  (session.protectedCapability != nil) == session.capabilityState.isActive
              }),
              Set(payloadKeys).count == payloadKeys.count,
              Set(referencedPayloadKeys) == Set(payloadKeys),
              Set(capabilitySessionIDs).count == capabilitySessionIDs.count,
              Set(capabilitySessionIDs) == Set(activeSessionIDs),
              snapshot.protectedCapabilityArtifacts.allSatisfy { capability in
                  snapshot.sessions.contains(where: {
                      $0.sessionID == capability.sessionID
                          && $0.capabilityState == capability.state
                          && $0.protectedCapability?.sha256 == capability.sha256
                  })
              } else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        return snapshot
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
            if report.snapshotSchemaVersion == CompletedActivitySnapshotV2.schemaVersion {
                let snapshot = try CompletedActivitySnapshotCanonicalCodecV2.decode(bytes)
                let activity = snapshot.payload.activity
                guard activity.reportID.lowercased() == report.id.uuidString.lowercased(),
                      activity.sourceActivityID.lowercased() == source.id.uuidString.lowercased(),
                      snapshot.payload.assetID == source.assetID else {
                    throw invalid()
                }
                continue
            }
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
// C52_BOUNDARY_ANCHOR: canonical-service-request-backup
enum C52ServiceRequestBackupValidationBoundaryV1 {
    static let persistentSchemaVersion = 39
    static let recordsSchemaVersion = 38
    static let validatesRecordAndEventDigests = true
    static let validatesDispositionPredecessors = true
    static let validatesWorkLinkPredecessorsAndReversals = true
    static let rejectsDuplicateCanonicalWorkLinks = true
}

enum C53ServiceReliabilityBackupPackageValidationV1 {
    static let persistentSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.targetPersistentSchemaVersion
    static let recordsSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.recordsSchemaVersion
    static let validatesAllSevenSourceFamilies = true
    static let validatesExactPredecessorClosure = true
    static let derivedMetricProjectionIsExcluded = true
    static let rawCapabilityIsExcluded = true

    static func validate(
        _ records: V4BackupRecordsV1,
        manifest: V4BackupManifestV1
    ) throws {
        guard records.recordsSchemaVersion >= recordsSchemaVersion
                || manifest.source.persistentSchemaVersion >= persistentSchemaVersion else {
            try C53ServiceReliabilityBackupEnrollmentV1.validate(records: records)
            return
        }
        guard records.recordsSchemaVersion == recordsSchemaVersion,
              manifest.source.persistentSchemaVersion == persistentSchemaVersion,
              validatesAllSevenSourceFamilies,
              validatesExactPredecessorClosure,
              derivedMetricProjectionIsExcluded,
              rawCapabilityIsExcluded else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        try C53ServiceReliabilityBackupEnrollmentV1.validate(
            records: records,
            workspaceID: manifest.source.workspaceID
        )
    }
}

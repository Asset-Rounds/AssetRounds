import Darwin
import Foundation
import SwiftData

enum BackupExportServiceError: Error, Equatable {
    case invalidGeneration
    case contextHasChanges
    case invalidAuthority
    case stalePreview
    case destinationInvalid
    case destinationExists
    case cancelled
    case insufficientStorage
    case sourceChanged
    case cleanupFailed
    case writeFailed
    case generationLeaseLost
}

@MainActor
enum BackupPackageLifecycleRouteV1 {
    case live(WorkspacePackageLifecycleDependenciesV1)
    case expiringCompatibility(BackupPackageCompatibilityPostureV1)
}

@MainActor
final class BackupExportService {
    private struct Rows {
        let sites: [Site]
        let assets: [Asset]
        let records: [WorkflowRecord]
        let observationAndTime: [UUID: ObservationAndTimeRow]
        let evidence: [EvidenceFile]
        let issues: [Issue]
        let packets: [Packet]
        let reports: [Report]
    }

    private struct StreamingSource: Equatable, Sendable {
        enum Location: Equatable, Sendable {
            case generatedRecords
            case generationRelative(String)
        }

        let path: String
        let mimeType: String
        let byteCount: Int
        let sha256: String
        let location: Location
    }

    private struct StreamingPrepared: Equatable, Sendable {
        let preview: BackupExportPreviewV1
        let manifest: V4BackupManifestV1
        let manifestData: Data
        let recordsData: Data
        let sources: [StreamingSource]
    }

    private struct OwnedStagingSource {
        let url: URL
        let device: UInt64
        let inode: UInt64
    }

    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let lifecycleRoute: BackupPackageLifecycleRouteV1
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity?
    private let storagePreflight: StoragePreflightService
    private let archiveLimits: StreamingArchiveLimitsV1
    private let archiveService: StreamingArchiveService
    private let now: () -> Date
    private let makeUUID: @Sendable () -> UUID
    private let appVersion: () -> String
    private let appBuild: () -> String
    private let fileManager: FileManager
    private let generationLeaseValidation: @Sendable () throws -> Void
    private var prepared: PreparedV4BackupV1?
    private var streamingPrepared: StreamingPrepared?

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        lifecycleRoute: BackupPackageLifecycleRouteV1,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        archiveLimits: StreamingArchiveLimitsV1 = .card17,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        },
        appBuild: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "0"
        },
        fileManager: FileManager = .default,
        generationLeaseValidation: @escaping @Sendable () throws -> Void = {}
    ) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.lifecycleRoute = lifecycleRoute
        self.storagePreflight = storagePreflight
        self.archiveLimits = archiveLimits
        self.archiveService = StreamingArchiveService(
            limits: archiveLimits,
            makeOperationID: makeUUID
        )
        self.now = now
        self.makeUUID = makeUUID
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.fileManager = fileManager
        self.generationLeaseValidation = generationLeaseValidation
        let root = generationRootURL.standardizedFileURL
        let dataRoot = root.deletingLastPathComponent().deletingLastPathComponent()
        if root.isFileURL,
           root.deletingLastPathComponent().lastPathComponent == "generations",
           dataRoot.lastPathComponent == "FieldEvidenceData",
           let id = UUID(uuidString: root.lastPathComponent),
           id.uuidString.lowercased() == root.lastPathComponent {
            rootIdentity = try? ReportPDFAnchoredFile.rootIdentity(at: root)
        } else {
            rootIdentity = nil
        }
    }

    convenience init(
        modelContext: ModelContext,
        generationRootURL: URL,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        archiveLimits: StreamingArchiveLimitsV1 = .card17,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        },
        appBuild: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "0"
        },
        fileManager: FileManager = .default,
        generationLeaseValidation: @escaping @Sendable () throws -> Void = {}
    ) {
        self.init(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            lifecycleRoute: .live(lifecycleDependencies),
            storagePreflight: storagePreflight,
            archiveLimits: archiveLimits,
            now: now,
            makeUUID: makeUUID,
            appVersion: appVersion,
            appBuild: appBuild,
            fileManager: fileManager,
            generationLeaseValidation: generationLeaseValidation
        )
    }

    convenience init(
        modelContext: ModelContext,
        generationRootURL: URL,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        archiveLimits: StreamingArchiveLimitsV1 = .card17,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        },
        appBuild: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "0"
        },
        fileManager: FileManager = .default,
        generationLeaseValidation: @escaping @Sendable () throws -> Void = {},
        compatibilityPosture: BackupPackageCompatibilityPostureV1 = .frozenLegacyCallersOnly
    ) {
        self.init(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            lifecycleRoute: .expiringCompatibility(compatibilityPosture),
            storagePreflight: storagePreflight,
            archiveLimits: archiveLimits,
            now: now,
            makeUUID: makeUUID,
            appVersion: appVersion,
            appBuild: appBuild,
            fileManager: fileManager,
            generationLeaseValidation: generationLeaseValidation
        )
    }

    func prepare() throws -> BackupExportPreviewV1 {
        try validateGenerationLease()
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        let value = try buildStreamingPrepared(
            previewID: makeUUID(),
            exportedAt: now()
        )
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        streamingPrepared = value
        try validateGenerationLease()
        return value.preview
    }

    /// Compatibility alias for callers introduced with the V23 streaming
    /// archive. All shipping preparation now selects the current writer.
    func prepareStreaming() throws -> BackupExportPreviewV1 {
        try prepare()
    }

    /// Test-only compatibility fixture seam for producing the historic V1
    /// directory package. Shipping call sites must use `prepare()`.
    func prepareCompatibilityFixtureLegacyDirectoryPackage() throws -> BackupExportPreviewV1 {
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        let value = try buildPrepared(
            previewID: makeUUID(),
            exportedAt: now()
        )
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        prepared = value
        return value.preview
    }

    func export(
        previewID: UUID,
        to destinationDirectoryURL: URL
    ) throws -> URL {
        try validateLifecycleScope(try fetchRows(), operation: .exportOpen)
        try exportStreaming(
            previewID: previewID,
            to: destinationDirectoryURL,
            cancellation: .none
        )
    }

    /// Test-only compatibility fixture seam for producing the historic V1
    /// directory package. Shipping call sites must use `export(previewID:to:)`.
    func exportCompatibilityFixtureLegacyDirectoryPackage(
        previewID: UUID,
        to destinationDirectoryURL: URL
    ) throws -> URL {
        try validateLifecycleScope(try fetchRows(), operation: .exportOpen)
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        guard let frozen = prepared, frozen.preview.id == previewID else {
            throw BackupExportServiceError.stalePreview
        }
        let rebuilt = try buildPrepared(
            previewID: previewID,
            exportedAt: frozen.manifest.exportedAt
        )
        guard rebuilt == frozen else {
            throw BackupExportServiceError.stalePreview
        }
        guard destinationDirectoryURL.isFileURL else {
            throw BackupExportServiceError.destinationInvalid
        }

        let destination = destinationDirectoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: destination.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw BackupExportServiceError.destinationInvalid
        }
        do {
            try storagePreflight.checkBackupExport(
                declaredPayloadByteCount: Int64(frozen.preview.declaredPayloadByteCount),
                onVolumeContaining: destination
            )
        } catch {
            throw error
        }

        let packageURL = destination.appendingPathComponent(
            "AssetRounds.fieldrecordbackup",
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw BackupExportServiceError.destinationExists
        }
        let wrapper = try makeFileWrapper(frozen)
        var coordinationError: NSError?
        var writeError: Error?
        var writtenPackageURL: URL?
        NSFileCoordinator().coordinate(
            writingItemAt: destination,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedDirectory in
            let coordinatedPackage = coordinatedDirectory.appendingPathComponent(
                packageURL.lastPathComponent,
                isDirectory: true
            )
            do {
                guard !fileManager.fileExists(atPath: coordinatedPackage.path) else {
                    throw BackupExportServiceError.destinationExists
                }
                try wrapper.write(
                    to: coordinatedPackage,
                    options: .atomic,
                    originalContentsURL: nil
                )
                writtenPackageURL = coordinatedPackage
                try verifyPackage(frozen, at: coordinatedPackage)
            } catch {
                writeError = error
            }
        }
        if coordinationError != nil {
            if let writtenPackageURL,
               fileManager.fileExists(atPath: writtenPackageURL.path) {
                try? fileManager.removeItem(at: writtenPackageURL)
            }
            throw BackupExportServiceError.writeFailed
        }
        if let writeError {
            if let writtenPackageURL,
               fileManager.fileExists(atPath: writtenPackageURL.path) {
                try? fileManager.removeItem(at: writtenPackageURL)
            }
            if let typed = writeError as? BackupExportServiceError {
                throw typed
            }
            throw BackupExportServiceError.writeFailed
        }
        prepared = nil
        return packageURL
    }

    /// Compatibility alias for callers introduced with the V23 streaming
    /// archive. `export(previewID:to:)` uses this same current writer.
    func exportStreaming(
        previewID: UUID,
        to destinationDirectoryURL: URL,
        cancellation: StreamingArchiveCancellationV1 = .none
    ) throws -> URL {
        try validateLifecycleScope(try fetchRows(), operation: .exportOpen)
        try validateGenerationLease()
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        guard let frozen = streamingPrepared,
              frozen.preview.id == previewID else {
            throw BackupExportServiceError.stalePreview
        }
        let rebuilt = try buildStreamingPrepared(
            previewID: previewID,
            exportedAt: frozen.manifest.exportedAt
        )
        guard rebuilt == frozen, !modelContext.hasChanges else {
            throw BackupExportServiceError.stalePreview
        }
        let destination = destinationDirectoryURL.standardizedFileURL
        guard destinationDirectoryURL.isFileURL,
              try itemType(at: destination) == .directory else {
            throw BackupExportServiceError.destinationInvalid
        }
        do {
            try storagePreflight.checkBackupExport(
                declaredPayloadByteCount: Int64(frozen.preview.declaredPayloadByteCount),
                onVolumeContaining: destination
            )
        } catch {
            throw mapStreamingExportError(error)
        }

        let packageURL = destination.appendingPathComponent(
            "AssetRounds.fieldrecordbackup",
            isDirectory: false
        )
        guard try itemType(at: packageURL) == nil else {
            throw BackupExportServiceError.destinationExists
        }
        let stagingRoot: URL
        guard let pinnedGenerationRootIdentity = rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        do {
            stagingRoot = try StoreGenerationFactory.backupImportStagingDirectory(
                containing: generationRootURL
            )
            guard try itemType(at: stagingRoot) == .directory else {
                throw BackupExportServiceError.invalidGeneration
            }
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: stagingRoot) {
                guard try self.itemType(at: stagingRoot) == .directory,
                      try ReportPDFAnchoredFile.rootIdentity(at: self.generationRootURL)
                        == pinnedGenerationRootIdentity else {
                    throw BackupExportServiceError.invalidGeneration
                }
            }
        } catch let error as BackupExportServiceError {
            throw error
        } catch {
            throw BackupExportServiceError.invalidGeneration
        }

        let stagingRootDescriptor = Darwin.open(
            stagingRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard stagingRootDescriptor >= 0 else {
            throw BackupExportServiceError.invalidGeneration
        }
        defer { _ = Darwin.close(stagingRootDescriptor) }
        var stagingRootInformation = stat()
        guard Darwin.fstat(stagingRootDescriptor, &stagingRootInformation) == 0,
              (stagingRootInformation.st_mode & S_IFMT) == S_IFDIR else {
            throw BackupExportServiceError.invalidGeneration
        }
        let stagingRootIdentity = StreamingArchiveRootIdentityV1(
            device: UInt64(stagingRootInformation.st_dev),
            inode: UInt64(stagingRootInformation.st_ino)
        )
        let generationSourceRootIdentity = StreamingArchiveRootIdentityV1(
            device: UInt64(pinnedGenerationRootIdentity.device),
            inode: UInt64(pinnedGenerationRootIdentity.inode)
        )

        let manifestSource = stagingRoot.appendingPathComponent(
            ".backup-export-\(uuid(previewID))-manifest.json"
        )
        let recordsSource = stagingRoot.appendingPathComponent(
            ".backup-export-\(uuid(previewID))-records.json"
        )
        var createdSources = [OwnedStagingSource]()
        var publishedURL: URL?
        do {
            createdSources.append(try writeOwnedStagingSource(
                frozen.manifestData,
                to: manifestSource,
                expectedRootIdentity: stagingRootIdentity
            ))
            createdSources.append(try writeOwnedStagingSource(
                frozen.recordsData,
                to: recordsSource,
                expectedRootIdentity: stagingRootIdentity
            ))
            try validateGenerationLease()

            var entries = [StreamingArchiveWriteEntryV1(
                path: "manifest.json",
                mimeType: "application/json",
                sourceRootURL: stagingRoot,
                sourceRelativePath: manifestSource.lastPathComponent,
                expectedSourceRootIdentity: stagingRootIdentity,
                expectedUncompressedByteCount: Int64(frozen.manifestData.count),
                expectedContentSHA256: CanonicalJSONV1.sha256(frozen.manifestData),
                compression: .stored
            )]
            entries.append(contentsOf: frozen.sources.map { source in
                let sourceRootURL: URL
                let sourceRelativePath: String
                let expectedSourceRootIdentity: StreamingArchiveRootIdentityV1
                switch source.location {
                case .generatedRecords:
                    sourceRootURL = stagingRoot
                    sourceRelativePath = recordsSource.lastPathComponent
                    expectedSourceRootIdentity = stagingRootIdentity
                case .generationRelative(let relativePath):
                    sourceRootURL = generationRootURL
                    sourceRelativePath = relativePath
                    expectedSourceRootIdentity = generationSourceRootIdentity
                }
                return StreamingArchiveWriteEntryV1(
                    path: source.path,
                    mimeType: source.mimeType,
                    sourceRootURL: sourceRootURL,
                    sourceRelativePath: sourceRelativePath,
                    expectedSourceRootIdentity: expectedSourceRootIdentity,
                    expectedUncompressedByteCount: Int64(source.byteCount),
                    expectedContentSHA256: source.sha256,
                    compression: .stored
                )
            })
            let plan = StreamingArchiveWritePlanV1(
                entries: entries,
                stagingDirectoryURL: stagingRoot
            )
            var coordinationError: NSError?
            var coordinatedResult: Result<StreamingArchiveWriteReceiptV1, Error>?
            NSFileCoordinator().coordinate(
                writingItemAt: destination,
                options: .forMerging,
                error: &coordinationError
            ) { coordinatedDirectory in
                let coordinatedPackage = coordinatedDirectory.appendingPathComponent(
                    packageURL.lastPathComponent,
                    isDirectory: false
                )
                coordinatedResult = Result {
                    try self.archiveService.write(
                        plan,
                        to: coordinatedPackage,
                        cancellation: cancellation,
                        storageCheck: { requiredBytes in
                            try self.storagePreflight.checkBackupExport(
                                declaredPayloadByteCount: requiredBytes,
                                onVolumeContaining: coordinatedDirectory
                            )
                        }
                    )
                }
            }
            guard coordinationError == nil, let coordinatedResult else {
                throw BackupExportServiceError.writeFailed
            }
            let receipt = try coordinatedResult.get()
            try validateGenerationLease()
            publishedURL = receipt.archiveURL
            guard receipt.index.entries.map(\.path) == entries
                    .sorted(by: { utf8Less($0.path, $1.path) })
                    .map(\.path),
                  receipt.index.uncompressedPayloadByteCount
                    == Int64(frozen.manifestData.count)
                        + Int64(frozen.preview.declaredPayloadByteCount),
                  try StreamingArchiveService.hasFormatMagic(at: receipt.archiveURL) else {
                throw BackupExportServiceError.writeFailed
            }
            try cleanupOwnedStagingSources(
                createdSources,
                within: stagingRoot,
                directoryDescriptor: stagingRootDescriptor,
                expectedRootIdentity: stagingRootIdentity
            )
            createdSources.removeAll()
            streamingPrepared = nil
            return receipt.archiveURL
        } catch {
            let original = error
            let cleaned = (try? cleanupOwnedStagingSources(
                createdSources,
                within: stagingRoot,
                directoryDescriptor: stagingRootDescriptor,
                expectedRootIdentity: stagingRootIdentity
            )) != nil
            if let publishedURL,
               (try? removeOwnedPublishedArchive(publishedURL, within: destination)) == nil {
                throw BackupExportServiceError.cleanupFailed
            }
            guard cleaned else { throw BackupExportServiceError.cleanupFailed }
            throw mapStreamingExportError(original)
        }
    }
}

private extension BackupExportService {
    func buildStreamingPrepared(
        previewID: UUID,
        exportedAt: Date
    ) throws -> StreamingPrepared {
        guard let rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        let sourceIdentity = try currentStreamingWorkspaceIdentity()
        let generationID = try currentStreamingGenerationID()
        let rows = try fetchRows()
        try validateLifecycleScope(rows, operation: .backup)
        try validateLifecycleScope(rows, operation: .archive)
        try validateGraph(rows)
        let deletionLedger: DeletionLedgerV2
        do {
            deletionLedger = try DeletionLedgerStore(context: modelContext).snapshot()
            try validateDeletionLedger(deletionLedger, rows: rows)
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        let mutationHistory: MutationHistorySnapshotV1
        do {
            mutationHistory = try MutationJournalStoreV1(
                modelContext: modelContext,
                identity: sourceIdentity,
                generationID: generationID
            ).exportSnapshot()
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        let records = try makeRecords(
            rows,
            deletionLedger: deletionLedger,
            mutationHistory: mutationHistory
        )
        let recordsData: Data
        do {
            recordsData = try BackupCanonicalEncoderV1().encodeRecords(records).data
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        guard Int64(recordsData.count) <= archiveLimits.maximumUncompressedEntryByteCount else {
            throw BackupExportServiceError.invalidAuthority
        }

        var sources = [StreamingSource(
            path: "records.json",
            mimeType: "application/json",
            byteCount: recordsData.count,
            sha256: CanonicalJSONV1.sha256(recordsData),
            location: .generatedRecords
        )]
        let normalizer = MediaNormalizerV1()
        for evidence in rows.evidence.sorted(by: { uuid($0.id) < uuid($1.id) }) {
            guard !Task.isCancelled else {
                throw BackupExportServiceError.cancelled
            }
            try validateGenerationLease()
            let canonicalID = uuid(evidence.id)
            guard evidence.relativePath == "evidence/\(canonicalID)/original.jpg",
                  evidence.thumbnailRelativePath
                    == "evidence/\(canonicalID)/thumbnail.jpg",
                  evidence.mimeType == "image/jpeg",
                  evidence.byteCount >= 0,
                  evidence.thumbnailByteCount >= 0,
                  Int64(evidence.byteCount)
                    <= archiveLimits.maximumUncompressedEntryByteCount,
                  Int64(evidence.thumbnailByteCount)
                    <= archiveLimits.maximumUncompressedEntryByteCount else {
                throw BackupExportServiceError.invalidAuthority
            }
            do {
                let original = try boundedStreamingRead(
                    evidence.relativePath,
                    expectedByteCount: Int64(evidence.byteCount),
                    expectedSHA256: evidence.sha256,
                    rootIdentity: rootIdentity
                )
                _ = try normalizer.validateCanonicalJPEG(original, kind: .original)
            }
            do {
                let thumbnail = try boundedStreamingRead(
                    evidence.thumbnailRelativePath,
                    expectedByteCount: Int64(evidence.thumbnailByteCount),
                    expectedSHA256: evidence.thumbnailSHA256,
                    rootIdentity: rootIdentity
                )
                _ = try normalizer.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            }
            sources.append(.init(
                path: "media/\(canonicalID).jpg",
                mimeType: "image/jpeg",
                byteCount: evidence.byteCount,
                sha256: evidence.sha256,
                location: .generationRelative(evidence.relativePath)
            ))
            sources.append(.init(
                path: "thumbnails/\(canonicalID).jpg",
                mimeType: "image/jpeg",
                byteCount: evidence.thumbnailByteCount,
                sha256: evidence.thumbnailSHA256,
                location: .generationRelative(evidence.thumbnailRelativePath)
            ))
        }

        for report in rows.reports.sorted(by: { uuid($0.id) < uuid($1.id) }) {
            guard !Task.isCancelled else {
                throw BackupExportServiceError.cancelled
            }
            try validateGenerationLease()
            let profile = try lifecycleProfile(for: report, rows: rows)
            let delivery: ReportDeliveryCoordinator
            do {
                delivery = try ReportDeliveryCoordinator(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    signPack: profile.package,
                    expectedRootIdentity: rootIdentity
                )
                try delivery.validateRecoveryAuthority(id: report.id)
            }
            catch { throw BackupExportServiceError.invalidAuthority }
            let canonicalID = uuid(report.id)
            guard (report.snapshotSchemaVersion == 1
                    || report.snapshotSchemaVersion == 2),
                  report.snapshotRelativePath == "snapshots/\(canonicalID).json" else {
                throw BackupExportServiceError.invalidAuthority
            }
            let snapshotByteCount: Int = try {
                let snapshot = try boundedStreamingRead(
                    report.snapshotRelativePath,
                    expectedByteCount: nil,
                    expectedSHA256: report.snapshotSHA256,
                    rootIdentity: rootIdentity
                )
                return snapshot.count
            }()
            sources.append(.init(
                path: report.snapshotRelativePath,
                mimeType: "application/json",
                byteCount: snapshotByteCount,
                sha256: report.snapshotSHA256,
                location: .generationRelative(report.snapshotRelativePath)
            ))
            switch ReportPDFState(rawValue: report.pdfState) {
            case .ready:
                let path = "pdfs/\(canonicalID).pdf"
                guard report.pdfRelativePath == path,
                      let expectedHash = report.pdfSHA256 else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let pdf = try boundedStreamingRead(
                    path,
                    expectedByteCount: nil,
                    expectedSHA256: expectedHash,
                    rootIdentity: rootIdentity
                )
                guard pdf.starts(with: Data("%PDF-".utf8)) else {
                    throw BackupExportServiceError.invalidAuthority
                }
                sources.append(.init(
                    path: path,
                    mimeType: "application/pdf",
                    byteCount: pdf.count,
                    sha256: expectedHash,
                    location: .generationRelative(path)
                ))
            case .pending, .failed:
                guard report.pdfRelativePath == nil, report.pdfSHA256 == nil else {
                    throw BackupExportServiceError.invalidAuthority
                }
            case nil:
                throw BackupExportServiceError.invalidAuthority
            }
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity,
              try currentStreamingWorkspaceIdentity() == sourceIdentity,
              try DeletionLedgerStore(context: modelContext).snapshot()
                == deletionLedger,
              try MutationJournalStoreV1(
                  modelContext: modelContext,
                  identity: sourceIdentity,
                  generationID: generationID
              ).exportSnapshot() == mutationHistory,
              !modelContext.hasChanges else {
            throw BackupExportServiceError.invalidGeneration
        }

        sources.sort { utf8Less($0.path, $1.path) }
        guard sources.count + 1 <= archiveLimits.maximumEntryCount else {
            throw BackupExportServiceError.invalidAuthority
        }
        var declaredPayloadByteCount = 0
        let entries = try sources.map { source -> V4BackupEntryV1 in
            let (next, overflow) = declaredPayloadByteCount.addingReportingOverflow(
                source.byteCount
            )
            guard !overflow else {
                throw BackupExportServiceError.invalidAuthority
            }
            guard Int64(next) <= archiveLimits.maximumUncompressedAggregateByteCount else {
                throw BackupExportServiceError.invalidAuthority
            }
            declaredPayloadByteCount = next
            return V4BackupEntryV1(
                byteCount: source.byteCount,
                mimeType: source.mimeType,
                path: source.path,
                sha256: source.sha256
            )
        }
        let packs = try manifestPacks(rows)
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: 4,
            consumedEvaluationRootIDs: rows.packets
                .filter(\.evaluationCounted)
                .map(\.stableRootID)
                .sorted { uuid($0) < uuid($1) },
            declaredPayloadByteCount: declaredPayloadByteCount,
            entries: entries,
            exportedAt: exportedAt,
            packs: packs,
            source: .init(
                appBuild: appBuild(),
                appVersion: appVersion(),
                persistentSchemaVersion: 5,
                replicaID: sourceIdentity.replicaID.rawValue,
                recordsSchemaVersion: 4,
                workspaceID: sourceIdentity.workspaceID.rawValue
            )
        )
        let manifestData: Data
        do {
            manifestData = try BackupCanonicalEncoderV1().encodeManifest(manifest).data
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        guard manifestData.count <= archiveLimits.maximumIndexByteCount,
              Int64(manifestData.count)
                <= archiveLimits.maximumUncompressedEntryByteCount else {
            throw BackupExportServiceError.invalidAuthority
        }
        return StreamingPrepared(
            preview: .init(
                id: previewID,
                signCount: rows.assets.count,
                reportCount: rows.reports.count,
                photoCount: rows.evidence.count,
                declaredPayloadByteCount: declaredPayloadByteCount
            ),
            manifest: manifest,
            manifestData: manifestData,
            recordsData: recordsData,
            sources: sources
        )
    }

    func currentStreamingWorkspaceIdentity() throws -> WorkspaceReplicaIdentityV1 {
        let generationID = try currentStreamingGenerationID()
        let applicationSupportURL = generationRootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        do {
            return try StoreGenerationFactory(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            ).currentWorkspaceIdentity(expectedGenerationID: generationID)
        } catch {
            throw BackupExportServiceError.invalidGeneration
        }
    }

    func currentStreamingGenerationID() throws -> UUID {
        guard let generationID = UUID(uuidString: generationRootURL.lastPathComponent),
              generationID.uuidString.lowercased()
                == generationRootURL.lastPathComponent else {
            throw BackupExportServiceError.invalidGeneration
        }
        return generationID
    }

    func buildPrepared(
        previewID: UUID,
        exportedAt: Date
    ) throws -> PreparedV4BackupV1 {
        guard let rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        let rows = try fetchRows()
        try validateLifecycleScope(rows, operation: .backup)
        try validateLifecycleScope(rows, operation: .archive)
        try validateGraph(rows)
        let records = try makeRecords(rows)
        let recordsData: Data
        do {
            recordsData = try BackupCanonicalEncoderV1().encodeRecords(records).data
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }

        var members = [V4BackupPackageMemberV1(
            path: "records.json",
            mimeType: "application/json",
            data: recordsData
        )]
        let normalizer = MediaNormalizerV1()
        for evidence in rows.evidence.sorted(by: { uuid($0.id) < uuid($1.id) }) {
            let canonicalID = uuid(evidence.id)
            guard evidence.relativePath == "evidence/\(canonicalID)/original.jpg",
                  evidence.thumbnailRelativePath
                    == "evidence/\(canonicalID)/thumbnail.jpg",
                  evidence.mimeType == "image/jpeg",
                  evidence.byteCount >= 0,
                  evidence.thumbnailByteCount >= 0 else {
                throw BackupExportServiceError.invalidAuthority
            }
            let original = try anchoredRead(evidence.relativePath, rootIdentity: rootIdentity)
            let thumbnail = try anchoredRead(
                evidence.thumbnailRelativePath,
                rootIdentity: rootIdentity
            )
            guard original.count == evidence.byteCount,
                  thumbnail.count == evidence.thumbnailByteCount,
                  CanonicalJSONV1.sha256(original) == evidence.sha256,
                  CanonicalJSONV1.sha256(thumbnail) == evidence.thumbnailSHA256 else {
                throw BackupExportServiceError.invalidAuthority
            }
            do {
                _ = try normalizer.validateCanonicalJPEG(original, kind: .original)
                _ = try normalizer.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            } catch {
                throw BackupExportServiceError.invalidAuthority
            }
            members.append(.init(
                path: "media/\(canonicalID).jpg",
                mimeType: "image/jpeg",
                data: original
            ))
            members.append(.init(
                path: "thumbnails/\(canonicalID).jpg",
                mimeType: "image/jpeg",
                data: thumbnail
            ))
        }

        for report in rows.reports.sorted(by: { uuid($0.id) < uuid($1.id) }) {
            let profile = try lifecycleProfile(for: report, rows: rows)
            let delivery: ReportDeliveryCoordinator
            do {
                delivery = try ReportDeliveryCoordinator(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    signPack: profile.package,
                    expectedRootIdentity: rootIdentity
                )
                try delivery.validateRecoveryAuthority(id: report.id)
            }
            catch { throw BackupExportServiceError.invalidAuthority }
            let canonicalID = uuid(report.id)
            guard (report.snapshotSchemaVersion == 1
                    || report.snapshotSchemaVersion == 2),
                  report.snapshotRelativePath == "snapshots/\(canonicalID).json" else {
                throw BackupExportServiceError.invalidAuthority
            }
            let snapshot = try anchoredRead(
                report.snapshotRelativePath,
                rootIdentity: rootIdentity
            )
            guard CanonicalJSONV1.sha256(snapshot) == report.snapshotSHA256 else {
                throw BackupExportServiceError.invalidAuthority
            }
            members.append(.init(
                path: "snapshots/\(canonicalID).json",
                mimeType: "application/json",
                data: snapshot
            ))
            switch ReportPDFState(rawValue: report.pdfState) {
            case .ready:
                guard report.pdfRelativePath == "pdfs/\(canonicalID).pdf",
                      let expectedHash = report.pdfSHA256 else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let pdf = try anchoredRead(
                    "pdfs/\(canonicalID).pdf",
                    rootIdentity: rootIdentity
                )
                guard CanonicalJSONV1.sha256(pdf) == expectedHash,
                      pdf.starts(with: Data("%PDF-".utf8)) else {
                    throw BackupExportServiceError.invalidAuthority
                }
                members.append(.init(
                    path: "pdfs/\(canonicalID).pdf",
                    mimeType: "application/pdf",
                    data: pdf
                ))
            case .pending, .failed:
                guard report.pdfRelativePath == nil, report.pdfSHA256 == nil else {
                    throw BackupExportServiceError.invalidAuthority
                }
            case nil:
                throw BackupExportServiceError.invalidAuthority
            }
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity,
              !modelContext.hasChanges else {
            throw BackupExportServiceError.invalidGeneration
        }

        members.sort { $0.path < $1.path }
        var entries: [V4BackupEntryV1] = []
        var declaredPayloadByteCount = 0
        for member in members {
            let (next, overflow) = declaredPayloadByteCount.addingReportingOverflow(
                member.data.count
            )
            guard !overflow else {
                throw BackupExportServiceError.invalidAuthority
            }
            declaredPayloadByteCount = next
            entries.append(.init(
                byteCount: member.data.count,
                mimeType: member.mimeType,
                path: member.path,
                sha256: CanonicalJSONV1.sha256(member.data)
            ))
        }
        let packs = try manifestPacks(rows)
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: 1,
            consumedEvaluationRootIDs: rows.packets
                .filter(\.evaluationCounted)
                .map(\.stableRootID)
                .sorted { uuid($0) < uuid($1) },
            declaredPayloadByteCount: declaredPayloadByteCount,
            entries: entries,
            exportedAt: exportedAt,
            packs: packs,
            source: .init(
                appBuild: appBuild(),
                appVersion: appVersion(),
                persistentSchemaVersion: 1,
                recordsSchemaVersion: 1
            )
        )
        do { _ = try BackupCanonicalEncoderV1().encodeManifest(manifest) }
        catch { throw BackupExportServiceError.invalidAuthority }
        return PreparedV4BackupV1(
            preview: .init(
                id: previewID,
                signCount: rows.assets.count,
                reportCount: rows.reports.count,
                photoCount: rows.evidence.count,
                declaredPayloadByteCount: declaredPayloadByteCount
            ),
            records: records,
            manifest: manifest,
            members: members
        )
    }

    struct StreamingSourceSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let linkCount: UInt64
        let byteCount: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    struct StreamingDirectoryIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    struct OpenedStreamingSource {
        let descriptor: Int32
        let ancestorDescriptors: [Int32]
        let ancestorIdentities: [StreamingDirectoryIdentity]
    }

    func boundedStreamingRead(
        _ relativePath: String,
        expectedByteCount: Int64?,
        expectedSHA256: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> Data {
        guard validRelativePath(relativePath),
              expectedByteCount.map({
                  $0 >= 0 && $0 <= archiveLimits.maximumUncompressedEntryByteCount
              }) ?? true else {
            throw BackupExportServiceError.invalidAuthority
        }
        let opened = try openStreamingSource(
            relativePath,
            rootIdentity: rootIdentity
        )
        defer {
            _ = Darwin.close(opened.descriptor)
            for descriptor in opened.ancestorDescriptors.reversed() {
                _ = Darwin.close(descriptor)
            }
        }
        let before = try streamingSourceSnapshot(opened.descriptor)
        guard before.byteCount >= 0,
              before.byteCount <= archiveLimits.maximumUncompressedEntryByteCount,
              before.byteCount <= Int64(Int.max),
              expectedByteCount.map({ $0 == before.byteCount }) ?? true else {
            throw BackupExportServiceError.invalidAuthority
        }

        var data = Data()
        data.reserveCapacity(Int(before.byteCount))
        var buffer = [UInt8](repeating: 0, count: archiveLimits.bufferByteCount)
        var remaining = Int64(before.byteCount)
        while remaining > 0 {
            guard !Task.isCancelled else {
                throw BackupExportServiceError.cancelled
            }
            let requested = min(buffer.count, Int(remaining))
            let count: Int = buffer.withUnsafeMutableBytes { raw in
                var result: Int
                repeat {
                    result = Darwin.read(opened.descriptor, raw.baseAddress, requested)
                } while result < 0 && errno == EINTR
                return result
            }
            guard count > 0 else {
                throw BackupExportServiceError.invalidAuthority
            }
            data.append(contentsOf: buffer[0..<count])
            remaining -= Int64(count)
        }
        var eofByte: UInt8 = 0
        let eofCount = withUnsafeMutablePointer(to: &eofByte) { pointer in
            var result: Int
            repeat {
                result = Darwin.read(opened.descriptor, pointer, 1)
            } while result < 0 && errno == EINTR
            return result
        }
        guard eofCount == 0,
              try streamingSourceSnapshot(opened.descriptor) == before,
              try streamingDirectoryIdentities(opened.ancestorDescriptors)
                == opened.ancestorIdentities,
              try streamingPathSnapshot(
                  relativePath,
                  rootIdentity: rootIdentity
              ) == before,
              try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity,
              data.count == Int(before.byteCount),
              CanonicalJSONV1.sha256(data) == expectedSHA256 else {
            throw BackupExportServiceError.invalidAuthority
        }
        return data
    }

    func openStreamingSource(
        _ relativePath: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> OpenedStreamingSource {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let rootDescriptor = Darwin.open(
            generationRootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw BackupExportServiceError.invalidGeneration
        }
        var ancestorDescriptors = [rootDescriptor]
        do {
            var rootInformation = stat()
            guard Darwin.fstat(rootDescriptor, &rootInformation) == 0,
                  (rootInformation.st_mode & S_IFMT) == S_IFDIR,
                  rootInformation.st_dev == rootIdentity.device,
                  rootInformation.st_ino == rootIdentity.inode else {
                throw BackupExportServiceError.invalidGeneration
            }
            for component in components.dropLast() {
                let child = Darwin.openat(
                    ancestorDescriptors[ancestorDescriptors.count - 1],
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw BackupExportServiceError.invalidAuthority
                }
                var childInformation = stat()
                guard Darwin.fstat(child, &childInformation) == 0,
                      (childInformation.st_mode & S_IFMT) == S_IFDIR else {
                    _ = Darwin.close(child)
                    throw BackupExportServiceError.invalidAuthority
                }
                ancestorDescriptors.append(child)
            }
            guard let leaf = components.last else {
                throw BackupExportServiceError.invalidAuthority
            }
            let file = Darwin.openat(
                ancestorDescriptors[ancestorDescriptors.count - 1],
                leaf,
                O_RDONLY | O_NOFOLLOW
            )
            guard file >= 0 else {
                throw BackupExportServiceError.invalidAuthority
            }
            let identities: [StreamingDirectoryIdentity]
            do {
                identities = try streamingDirectoryIdentities(
                    ancestorDescriptors
                )
            } catch {
                _ = Darwin.close(file)
                throw error
            }
            return OpenedStreamingSource(
                descriptor: file,
                ancestorDescriptors: ancestorDescriptors,
                ancestorIdentities: identities
            )
        } catch {
            for descriptor in ancestorDescriptors.reversed() {
                _ = Darwin.close(descriptor)
            }
            throw error
        }
    }

    func streamingDirectoryIdentities(
        _ descriptors: [Int32]
    ) throws -> [StreamingDirectoryIdentity] {
        try descriptors.map { descriptor in
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  (information.st_mode & S_IFMT) == S_IFDIR else {
                throw BackupExportServiceError.invalidAuthority
            }
            return StreamingDirectoryIdentity(
                device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino)
            )
        }
    }

    func streamingSourceSnapshot(_ descriptor: Int32) throws -> StreamingSourceSnapshot {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1 else {
            throw BackupExportServiceError.invalidAuthority
        }
        return StreamingSourceSnapshot(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino),
            linkCount: UInt64(information.st_nlink),
            byteCount: Int64(information.st_size),
            modifiedSeconds: Int64(information.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(information.st_mtimespec.tv_nsec),
            changedSeconds: Int64(information.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(information.st_ctimespec.tv_nsec)
        )
    }

    func streamingPathSnapshot(
        _ relativePath: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> StreamingSourceSnapshot {
        let opened = try openStreamingSource(
            relativePath,
            rootIdentity: rootIdentity
        )
        defer {
            _ = Darwin.close(opened.descriptor)
            for descriptor in opened.ancestorDescriptors.reversed() {
                _ = Darwin.close(descriptor)
            }
        }
        guard try streamingDirectoryIdentities(opened.ancestorDescriptors)
                == opened.ancestorIdentities else {
            throw BackupExportServiceError.invalidAuthority
        }
        return try streamingSourceSnapshot(opened.descriptor)
    }

    func anchoredRead(
        _ relativePath: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> Data {
        guard validRelativePath(relativePath) else {
            throw BackupExportServiceError.invalidAuthority
        }
        do {
            return try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(relativePath),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func fetchRows() throws -> Rows {
        do {
            return Rows(
                sites: try modelContext.fetch(FetchDescriptor<Site>()),
                assets: try modelContext.fetch(FetchDescriptor<Asset>()),
                records: try modelContext.fetch(FetchDescriptor<WorkflowRecord>()),
                observationAndTime: try ObservationAndTimeRowStoreV1.validatedIndex(
                    in: modelContext
                ),
                evidence: try modelContext.fetch(FetchDescriptor<EvidenceFile>()),
                issues: try modelContext.fetch(FetchDescriptor<Issue>()),
                packets: try modelContext.fetch(FetchDescriptor<Packet>()),
                reports: try modelContext.fetch(FetchDescriptor<Report>())
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func validateGraph(_ rows: Rows) throws {
        do {
            try KernelBackupRestoreRegistryV4.validate()
            let schema = try KernelPersistenceV4Schema.descriptor()
            guard schema.runtimePosture == .dormantStatic,
                  !schema.activationEnabled else {
                throw BackupExportServiceError.invalidAuthority
            }
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        guard unique(rows.sites.map(\.id)),
              unique(rows.assets.map(\.id)),
              unique(rows.records.map(\.id)),
              unique(rows.evidence.map(\.id)),
              unique(rows.issues.map(\.id)),
              unique(rows.packets.map(\.id)),
              unique(rows.packets.map(\.stableRootID)),
              unique(rows.reports.map(\.id)),
              rows.sites.allSatisfy({ $0.schemaVersion == 1 }),
              rows.assets.allSatisfy({ $0.schemaVersion == 1 }),
              rows.records.allSatisfy({ $0.schemaVersion == 1 }),
              rows.evidence.allSatisfy({ $0.schemaVersion == 1 }),
              rows.issues.allSatisfy({ $0.schemaVersion == 1 }),
              rows.packets.allSatisfy({ $0.schemaVersion == 1 }),
              rows.reports.allSatisfy({ $0.schemaVersion == 1 }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let siteIDs = Set(rows.sites.map(\.id))
        let assetIDs = Set(rows.assets.map(\.id))
        let recordIDs = Set(rows.records.map(\.id))
        let issueIDs = Set(rows.issues.map(\.id))
        let packetIDs = Set(rows.packets.map(\.id))
        let recordsByID = Dictionary(uniqueKeysWithValues: rows.records.map { ($0.id, $0) })
        let issuesByID = Dictionary(uniqueKeysWithValues: rows.issues.map { ($0.id, $0) })
        let packetsByID = Dictionary(uniqueKeysWithValues: rows.packets.map { ($0.id, $0) })
        let reportsByID = Dictionary(uniqueKeysWithValues: rows.reports.map { ($0.id, $0) })
        let profilesByAsset: [UUID: WorkspacePackageLifecycleProfileV1]
        do {
            profilesByAsset = try Dictionary(uniqueKeysWithValues: rows.assets.map { asset in
                let release = try PackageReleaseIdentityV1(
                    packageID: asset.packID,
                    schemaVersion: asset.packSchemaVersion,
                    contentVersion: asset.packContentVersion
                )
                return (asset.id, try lifecycleProfile(release))
            })
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        let validRecordRelationships = rows.records.allSatisfy { record in
            guard let revisionKind = WorkflowRevisionKind(rawValue: record.revisionKind),
                  let state = WorkflowState(rawValue: record.state),
                  let profile = profilesByAsset[record.assetID],
                  let stage = try? profile.stage(record.stage),
                  (state == .draft && record.outcomeKey == nil)
                    || (state == .completed
                        && stage.outcomeKeys.contains(record.outcomeKey ?? "")),
                  let revisionRoot = recordsByID[record.recordRevisionRootID],
                  revisionRoot.assetID == record.assetID,
                  revisionRoot.revisionKind == WorkflowRevisionKind.original.rawValue,
                  revisionRoot.recordRevisionRootID == revisionRoot.id,
                  revisionRoot.revisesRecordID == nil,
                  revisionRoot.evidenceSourceRecordID == nil,
                  record.parentRecordID.map({
                      recordsByID[$0]?.assetID == record.assetID
                  }) ?? true,
                  record.issueID.map({ issuesByID[$0]?.assetID == record.assetID }) ?? true,
                  record.packetID.map({ packetsByID[$0] != nil }) ?? true else {
                return false
            }
            switch revisionKind {
            case .original:
                return record.recordRevisionRootID == record.id
                    && record.revisesRecordID == nil
                    && record.evidenceSourceRecordID == nil
            case .clericalCorrection:
                guard let revisedID = record.revisesRecordID,
                      let sourceID = record.evidenceSourceRecordID,
                      let revised = recordsByID[revisedID],
                      let source = recordsByID[sourceID] else {
                    return false
                }
                return record.recordRevisionRootID != record.id
                    && revised.assetID == record.assetID
                    && revised.recordRevisionRootID == record.recordRevisionRootID
                    && source.id == record.recordRevisionRootID
                    && source.assetID == record.assetID
                    && record.parentRecordID == revised.parentRecordID
                    && record.issueID == revised.issueID
                    && record.packetID == revised.packetID
            }
        }
        let validPacketOwnership = rows.packets.allSatisfy { packet in
            var owners = Set<UUID>()
            if let currentID = packet.currentRecordID,
               let current = recordsByID[currentID] {
                owners.insert(current.assetID)
            }
            for record in rows.records where record.packetID == packet.id {
                owners.insert(record.assetID)
            }
            for report in rows.reports where report.packetID == packet.id {
                guard let source = recordsByID[report.sourceRecordID] else { return false }
                owners.insert(source.assetID)
            }
            return packet.currentRecordID == nil ? owners.isEmpty : owners.count == 1
        }
        guard rows.assets.allSatisfy({ asset in
                  siteIDs.contains(asset.siteID)
                    && profilesByAsset[asset.id] != nil
              }),
              rows.records.allSatisfy({ record in
                  let profile = profilesByAsset[record.assetID]
                  return assetIDs.contains(record.assetID)
                    && record.packetID.map(packetIDs.contains) ?? true
                    && record.issueID.map(issueIDs.contains) ?? true
                    && record.parentRecordID.map(recordIDs.contains) ?? true
                    && record.revisesRecordID.map(recordIDs.contains) ?? true
                    && record.evidenceSourceRecordID.map(recordIDs.contains) ?? true
                    && recordIDs.contains(record.recordRevisionRootID)
                    && WorkflowRevisionKind(rawValue: record.revisionKind) != nil
                    && WorkflowStage(rawValue: record.stage) != nil
                    && WorkflowState(rawValue: record.state) != nil
                    && record.draftStepKey.map({ WorkflowDraftStep(rawValue: $0) != nil }) ?? true
                    && record.packID == profile?.release.packageID
                    && record.packSchemaVersion == profile?.release.schemaVersion
                    && record.packContentVersion == profile?.release.contentVersion
                    && record.pdfTemplateID == profile?.pdfTemplate.id
                    && record.pdfTemplateVersion == profile?.pdfTemplate.version
              }),
              validRecordRelationships,
              rows.evidence.allSatisfy({ evidence in
                  guard let owner = recordsByID[evidence.recordID],
                        let profile = profilesByAsset[owner.assetID] else {
                      return false
                  }
                  return profile.evidencePurposes.contains {
                      $0.key == evidence.purposeKey
                  }
              }),
              rows.issues.allSatisfy({ issue in
                  let profile = profilesByAsset[issue.assetID]
                  return assetIDs.contains(issue.assetID)
                    && recordsByID[issue.openedByRecordID]?.assetID == issue.assetID
                    && profile?.package.issueLabels.contains(where: {
                        $0.key == issue.labelKey
                            && $0.display == issue.labelDisplaySnapshot
                    }) == true
                    && issue.resolvedByRecordID.map({
                        recordsByID[$0]?.assetID == issue.assetID
                    }) ?? true
                    && IssueStatus(rawValue: issue.status) != nil
              }),
              validPacketOwnership,
              rows.packets.allSatisfy({ packet in
                  if let current = packet.currentRecordID {
                      return packet.contentDeletedAt == nil
                        && rows.records.filter({ $0.id == current }).count == 1
                        && rows.records.first(where: { $0.id == current })?.packetID
                            == packet.id
                  }
                  return packet.evaluationCounted
                    && packet.contentDeletedAt != nil
                    && !rows.records.contains(where: { $0.packetID == packet.id })
                    && !rows.reports.contains(where: { $0.packetID == packet.id })
              }),
              rows.reports.allSatisfy({ report in
                  packetIDs.contains(report.packetID)
                    && recordIDs.contains(report.sourceRecordID)
                    && report.replacesReportID.map({ replacedID in
                        guard let replaced = reportsByID[replacedID] else { return false }
                        return replaced.packetID == report.packetID
                            && replaced.createdAt <= report.createdAt
                    }) ?? true
                    && ReportPDFState(rawValue: report.pdfState) != nil
              }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        try requireAcyclic(rows.records, id: \.id, next: \.parentRecordID)
        try requireAcyclic(rows.records, id: \.id, next: \.revisesRecordID)
        try requireAcyclic(rows.reports, id: \.id, next: \.replacesReportID)
        guard unique(rows.records.compactMap(\.revisesRecordID)),
              unique(rows.reports.compactMap(\.replacesReportID)) else {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func lifecycleProfile(
        for report: Report,
        rows: Rows
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        guard let record = rows.records.first(where: { $0.id == report.sourceRecordID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        do {
            return try lifecycleProfile(
                PackageReleaseIdentityV1(
                    packageID: record.packID,
                    schemaVersion: record.packSchemaVersion,
                    contentVersion: record.packContentVersion
                )
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func validateLifecycleScope(
        _ rows: Rows,
        operation: WorkspacePackageLifecycleOperationV1
    ) throws {
        guard case let .live(lifecycleDependencies) = lifecycleRoute else {
            guard case let .expiringCompatibility(posture) = lifecycleRoute,
                  posture == .frozenLegacyCallersOnly else {
                throw BackupExportServiceError.invalidAuthority
            }
            return
        }
        guard lifecycleDependencies.generationRootURL.standardizedFileURL
                == generationRootURL,
              lifecycleDependencies.generationID == (try currentStreamingGenerationID()),
              lifecycleDependencies.workspaceID
                == (try currentStreamingWorkspaceIdentity()).workspaceID else {
            throw BackupExportServiceError.invalidAuthority
        }
        let pairs: [(WorkspaceEntityKindV1, UUID)] =
            rows.sites.map { (.site, $0.id) }
            + rows.assets.map { (.asset, $0.id) }
            + rows.records.map { (.workflowRecord, $0.id) }
            + rows.evidence.map { (.evidenceFile, $0.id) }
            + rows.issues.map { (.issue, $0.id) }
            + rows.packets.map { (.packet, $0.id) }
            + rows.reports.map { (.report, $0.id) }
        let identities: [WorkspaceEntityIdentityV1]
        do {
            identities = try pairs.map { try .init(kind: $0.0, id: $0.1) }
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        let initial = try lifecycleDependencies.writer.currentRevision()
        guard initial.workspaceID == lifecycleDependencies.workspaceID,
              initial.generationID == lifecycleDependencies.generationID else {
            throw BackupExportServiceError.invalidAuthority
        }
        for start in stride(from: 0, to: identities.count, by: 256) {
            let slice = Array(identities[start..<min(start + 256, identities.count)])
            let request: WorkspacePackageLifecycleQueryRequestV1
            do {
                request = try .init(
                    workspaceID: lifecycleDependencies.workspaceID,
                    generationID: lifecycleDependencies.generationID,
                    operation: operation,
                    identities: slice
                )
                let result = try lifecycleDependencies.writer.query(request)
                guard result.existingIdentities == request.identities,
                      result.revision.revision == initial.revision else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let expectedBindings = rows.assets.filter { asset in
                    slice.contains(where: { $0.kind == .asset && $0.id == asset.id })
                }.map {
                    WorkspacePackageBindingV1(
                        assetID: $0.id,
                        packageID: $0.packID,
                        packageSchemaVersion: $0.packSchemaVersion,
                        packageContentVersion: $0.packContentVersion
                    )
                }.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
                guard result.packageBindings == expectedBindings else {
                    throw BackupExportServiceError.invalidAuthority
                }
            } catch {
                throw BackupExportServiceError.invalidAuthority
            }
        }
        guard try lifecycleDependencies.writer.currentRevision() == initial else {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func lifecycleProfile(
        _ release: PackageReleaseIdentityV1
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        do {
            switch lifecycleRoute {
            case let .live(dependencies):
                return try dependencies.profileRegistry.resolve(release)
            case let .expiringCompatibility(posture):
                guard posture == .frozenLegacyCallersOnly else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let profile = try WorkspacePackageLifecycleCompatibilityV1
                    .legacyV3Profile(package: .illuminatedSignV1)
                guard profile.release == release else {
                    throw BackupExportServiceError.invalidAuthority
                }
                return profile
            }
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func manifestPacks(_ rows: Rows) throws -> [V4BackupPackV1] {
        do {
            let releases = try rows.assets.map {
                try PackageReleaseIdentityV1(
                    packageID: $0.packID,
                    schemaVersion: $0.packSchemaVersion,
                    contentVersion: $0.packContentVersion
                )
            } + rows.records.map {
                try PackageReleaseIdentityV1(
                    packageID: $0.packID,
                    schemaVersion: $0.packSchemaVersion,
                    contentVersion: $0.packContentVersion
                )
            }
            return Set(releases).sorted().map {
                V4BackupPackV1(
                    contentVersion: $0.contentVersion,
                    packID: $0.packageID,
                    schemaVersion: $0.schemaVersion
                )
            }
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func makeRecords(
        _ rows: Rows,
        deletionLedger: DeletionLedgerV2? = nil,
        mutationHistory: MutationHistorySnapshotV1? = nil
    ) throws -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            assets: rows.assets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, siteID: $0.siteID,
                    packID: $0.packID, packSchemaVersion: $0.packSchemaVersion,
                    packContentVersion: $0.packContentVersion, label: $0.label,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            deletionLedger: deletionLedger,
            evidenceFiles: rows.evidence.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, recordID: $0.recordID,
                    purposeKey: $0.purposeKey, relativePath: $0.relativePath,
                    mimeType: $0.mimeType, byteCount: $0.byteCount,
                    sha256: $0.sha256, createdAt: $0.createdAt,
                    thumbnailRelativePath: $0.thumbnailRelativePath,
                    thumbnailByteCount: $0.thumbnailByteCount,
                    thumbnailSHA256: $0.thumbnailSHA256
                )
            }.sorted(by: dtoOrder),
            issues: rows.issues.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, assetID: $0.assetID,
                    openedByRecordID: $0.openedByRecordID, labelKey: $0.labelKey,
                    labelDisplaySnapshot: $0.labelDisplaySnapshot, status: $0.status,
                    resolvedByRecordID: $0.resolvedByRecordID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            mutationHistory: mutationHistory,
            packets: rows.packets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    stableRootID: $0.stableRootID,
                    currentRecordID: $0.currentRecordID,
                    evaluationCounted: $0.evaluationCounted,
                    contentDeletedAt: $0.contentDeletedAt, createdAt: $0.createdAt
                )
            }.sorted(by: dtoOrder),
            recordsSchemaVersion: mutationHistory == nil
                ? (deletionLedger == nil ? 1 : 2)
                : 4,
            reports: rows.reports.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    packetID: $0.packetID, sourceRecordID: $0.sourceRecordID,
                    snapshotSchemaVersion: $0.snapshotSchemaVersion,
                    snapshotRelativePath: $0.snapshotRelativePath,
                    snapshotSHA256: $0.snapshotSHA256, pdfState: $0.pdfState,
                    pdfRelativePath: $0.pdfRelativePath, pdfSHA256: $0.pdfSHA256,
                    createdAt: $0.createdAt, replacesReportID: $0.replacesReportID
                )
            }.sorted(by: dtoOrder),
            sites: rows.sites.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, label: $0.label,
                    address: $0.address, timeZoneID: $0.timeZoneID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            workflowRecords: try rows.records.map { record in
                guard let companion = rows.observationAndTime[record.id] else {
                    throw BackupExportServiceError.invalidAuthority
                }
                return workflowDTO(record, observationAndTime: companion)
            }.sorted(by: dtoOrder)
        )
    }

    func validateDeletionLedger(_ ledger: DeletionLedgerV2, rows: Rows) throws {
        try ledger.validate()
        guard ledger.entries.count <= DeletionLedgerV2.maximumEntryCount else {
            throw BackupExportServiceError.invalidAuthority
        }
        let deleted = Set(ledger.entries.map(\.identity))
        func identity(_ kind: DeletionRecordKindV2, _ id: UUID) throws
            -> DeletionIdentityV2 {
            try DeletionIdentityV2(kind: kind, id: id)
        }
        guard try rows.sites.allSatisfy({
                  !deleted.contains(try identity(.site, $0.id))
              }),
              try rows.assets.allSatisfy({
                  !deleted.contains(try identity(.asset, $0.id))
              }),
              try rows.records.allSatisfy({
                  !deleted.contains(try identity(.workflowRecord, $0.id))
              }),
              try rows.evidence.allSatisfy({
                  !deleted.contains(try identity(.evidenceFile, $0.id))
              }),
              try rows.issues.allSatisfy({
                  !deleted.contains(try identity(.issue, $0.id))
              }),
              try rows.reports.allSatisfy({
                  !deleted.contains(try identity(.report, $0.id))
              }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let byIdentity = Dictionary(
            uniqueKeysWithValues: ledger.entries.map { ($0.identity, $0) }
        )
        for packet in rows.packets {
            let packetIdentity = try identity(.packet, packet.id)
            if packet.currentRecordID == nil {
                guard packet.evaluationCounted,
                      let deletedAt = packet.contentDeletedAt,
                      byIdentity[packetIdentity]?.deletedAt == deletedAt else {
                    throw BackupExportServiceError.invalidAuthority
                }
            } else if byIdentity[packetIdentity] != nil {
                throw BackupExportServiceError.invalidAuthority
            }
        }
    }

    func workflowDTO(
        _ value: WorkflowRecord,
        observationAndTime: ObservationAndTimeRow
    ) -> V4BackupWorkflowRecordDTO {
        .init(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: value.packetID, issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage, state: value.state,
            draftStepKey: value.draftStepKey, startedAt: value.startedAt,
            completedAt: value.completedAt, observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID, utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate, localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey, couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID,
            observationBasisV1Data: observationAndTime.observationBasisV1Data,
            temporalContextV1Data: observationAndTime.temporalContextV1Data
        )
    }
}

private extension BackupExportService {
    func makeFileWrapper(_ value: PreparedV4BackupV1) throws -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let manifestData = try BackupCanonicalEncoderV1().encodeManifest(value.manifest).data
        try add(
            V4BackupPackageMemberV1(
                path: "manifest.json", mimeType: "application/json", data: manifestData
            ),
            to: root
        )
        for member in value.members { try add(member, to: root) }
        return root
    }

    func add(_ member: V4BackupPackageMemberV1, to root: FileWrapper) throws {
        let components = member.path.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw BackupExportServiceError.invalidAuthority
        }
        var directory = root
        for component in components.dropLast() {
            if let existing = directory.fileWrappers?[component] {
                guard existing.isDirectory else {
                    throw BackupExportServiceError.invalidAuthority
                }
                directory = existing
            } else {
                let child = FileWrapper(directoryWithFileWrappers: [:])
                child.preferredFilename = component
                directory.addFileWrapper(child)
                directory = child
            }
        }
        let leaf = FileWrapper(regularFileWithContents: member.data)
        leaf.preferredFilename = components.last
        guard directory.fileWrappers?[components.last!] == nil else {
            throw BackupExportServiceError.invalidAuthority
        }
        directory.addFileWrapper(leaf)
    }

    func verifyPackage(_ value: PreparedV4BackupV1, at url: URL) throws {
        let expectedManifest = try BackupCanonicalEncoderV1().encodeManifest(
            value.manifest
        ).data
        let expected = Dictionary(uniqueKeysWithValues:
            [("manifest.json", expectedManifest)]
                + value.members.map { ($0.path, $0.data) }
        )
        let wrapper = try FileWrapper(url: url, options: [.immediate])
        var actual: [String: Data] = [:]
        try flatten(wrapper, prefix: "", into: &actual)
        guard actual == expected else {
            throw BackupExportServiceError.writeFailed
        }
    }

    func flatten(
        _ wrapper: FileWrapper,
        prefix: String,
        into output: inout [String: Data]
    ) throws {
        guard !wrapper.isSymbolicLink else {
            throw BackupExportServiceError.writeFailed
        }
        if wrapper.isRegularFile {
            guard !prefix.isEmpty, let data = wrapper.regularFileContents,
                  output[prefix] == nil else {
                throw BackupExportServiceError.writeFailed
            }
            output[prefix] = data
            return
        }
        guard wrapper.isDirectory, let children = wrapper.fileWrappers else {
            throw BackupExportServiceError.writeFailed
        }
        for (name, child) in children {
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                throw BackupExportServiceError.writeFailed
            }
            let childPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            try flatten(child, prefix: childPath, into: &output)
        }
    }

    func validRelativePath(_ value: String) -> Bool {
        value == value.precomposedStringWithCanonicalMapping
            && !value.hasPrefix("/")
            && value.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    enum LocalItemType { case directory, regular }

    func itemType(at url: URL) throws -> LocalItemType? {
        var information = stat()
        if Darwin.lstat(url.standardizedFileURL.path, &information) != 0 {
            if errno == ENOENT { return nil }
            throw BackupExportServiceError.destinationInvalid
        }
        switch information.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFREG:
            guard information.st_nlink == 1 else {
                throw BackupExportServiceError.destinationInvalid
            }
            return .regular
        default:
            throw BackupExportServiceError.destinationInvalid
        }
    }

    func writeOwnedStagingSource(
        _ data: Data,
        to url: URL,
        expectedRootIdentity: StreamingArchiveRootIdentityV1
    ) throws -> OwnedStagingSource {
        let value = url.standardizedFileURL
        let stagingRoot = value.deletingLastPathComponent()
        guard value.lastPathComponent.hasPrefix(".backup-export-"),
              value.lastPathComponent.hasSuffix(".json"),
              Int64(data.count) <= archiveLimits.maximumUncompressedEntryByteCount,
              try itemType(at: value) == nil else {
            throw BackupExportServiceError.invalidAuthority
        }
        let parent = Darwin.open(
            stagingRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parent >= 0 else {
            throw BackupExportServiceError.invalidGeneration
        }
        defer { _ = Darwin.close(parent) }
        var parentInformation = stat()
        guard Darwin.fstat(parent, &parentInformation) == 0,
              (parentInformation.st_mode & S_IFMT) == S_IFDIR,
              UInt64(parentInformation.st_dev) == expectedRootIdentity.device,
              UInt64(parentInformation.st_ino) == expectedRootIdentity.inode else {
            throw BackupExportServiceError.invalidGeneration
        }
        let descriptor = Darwin.openat(
            parent,
            value.lastPathComponent,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw BackupExportServiceError.writeFailed
        }
        var initialInformation = stat()
        guard Darwin.fstat(descriptor, &initialInformation) == 0 else {
            _ = Darwin.close(descriptor)
            throw BackupExportServiceError.cleanupFailed
        }
        let expectedDevice = initialInformation.st_dev
        let expectedInode = initialInformation.st_ino
        guard (initialInformation.st_mode & S_IFMT) == S_IFREG,
              initialInformation.st_nlink == 1,
              initialInformation.st_size == 0 else {
            _ = Darwin.close(descriptor)
            var current = stat()
            if Darwin.fstatat(
                parent,
                value.lastPathComponent,
                &current,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
               current.st_dev == expectedDevice,
               current.st_ino == expectedInode {
                _ = Darwin.unlinkat(parent, value.lastPathComponent, 0)
                _ = Darwin.fsync(parent)
            }
            throw BackupExportServiceError.writeFailed
        }
        var keep = false
        defer {
            _ = Darwin.close(descriptor)
            if !keep {
                var current = stat()
                if Darwin.fstatat(
                    parent,
                    value.lastPathComponent,
                    &current,
                    AT_SYMLINK_NOFOLLOW
                ) == 0,
                   (current.st_mode & S_IFMT) == S_IFREG,
                   current.st_nlink == 1,
                   current.st_dev == expectedDevice,
                   current.st_ino == expectedInode {
                    _ = Darwin.unlinkat(parent, value.lastPathComponent, 0)
                    _ = Darwin.fsync(parent)
                }
            }
        }
        try ProtectedFilePolicyV1.applyAndVerify(
            .stagingFile,
            relativePath: value.lastPathComponent,
            within: stagingRoot
        ) {
            let currentRootDescriptor = Darwin.open(
                stagingRoot.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard currentRootDescriptor >= 0 else {
                throw BackupExportServiceError.sourceChanged
            }
            defer { _ = Darwin.close(currentRootDescriptor) }
            var currentRoot = stat()
            var current = stat()
            var currentPath = stat()
            guard Darwin.fstat(currentRootDescriptor, &currentRoot) == 0,
                  (currentRoot.st_mode & S_IFMT) == S_IFDIR,
                  UInt64(currentRoot.st_dev) == expectedRootIdentity.device,
                  UInt64(currentRoot.st_ino) == expectedRootIdentity.inode,
                  Darwin.fstat(descriptor, &current) == 0,
                  current.st_dev == expectedDevice,
                  current.st_ino == expectedInode,
                  current.st_nlink == 1,
                  current.st_size == 0,
                  Darwin.fstatat(
                    currentRootDescriptor,
                    value.lastPathComponent,
                    &currentPath,
                    AT_SYMLINK_NOFOLLOW
                  ) == 0,
                  (currentPath.st_mode & S_IFMT) == S_IFREG,
                  currentPath.st_dev == expectedDevice,
                  currentPath.st_ino == expectedInode,
                  currentPath.st_nlink == 1,
                  currentPath.st_size == 0 else {
                throw BackupExportServiceError.sourceChanged
            }
        }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let requested = min(
                    archiveLimits.bufferByteCount,
                    raw.count - offset
                )
                var count: Int
                repeat {
                    count = Darwin.write(
                        descriptor,
                        raw.baseAddress?.advanced(by: offset),
                        requested
                    )
                } while count < 0 && errno == EINTR
                guard count > 0 else {
                    throw BackupExportServiceError.writeFailed
                }
                offset += count
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw BackupExportServiceError.writeFailed
        }
        var information = stat()
        var pathInformation = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_dev == expectedDevice,
              information.st_ino == expectedInode,
              information.st_size == Int64(data.count),
              Darwin.fstatat(
                parent,
                value.lastPathComponent,
                &pathInformation,
                AT_SYMLINK_NOFOLLOW
              ) == 0,
              pathInformation.st_dev == expectedDevice,
              pathInformation.st_ino == expectedInode,
              pathInformation.st_nlink == 1,
              pathInformation.st_size == Int64(data.count) else {
            throw BackupExportServiceError.writeFailed
        }
        guard Darwin.fsync(parent) == 0 else {
            throw BackupExportServiceError.writeFailed
        }
        keep = true
        return OwnedStagingSource(
            url: value,
            device: UInt64(expectedDevice),
            inode: UInt64(expectedInode)
        )
    }

    func cleanupOwnedStagingSources(
        _ sources: [OwnedStagingSource],
        within stagingRootURL: URL,
        directoryDescriptor: Int32,
        expectedRootIdentity: StreamingArchiveRootIdentityV1
    ) throws {
        let root = stagingRootURL.standardizedFileURL
        var rootInformation = stat()
        guard Darwin.fstat(directoryDescriptor, &rootInformation) == 0,
              (rootInformation.st_mode & S_IFMT) == S_IFDIR,
              UInt64(rootInformation.st_dev) == expectedRootIdentity.device,
              UInt64(rootInformation.st_ino) == expectedRootIdentity.inode else {
            throw BackupExportServiceError.cleanupFailed
        }
        for source in sources.reversed() {
            let value = source.url.standardizedFileURL
            let name = value.lastPathComponent
            guard value.deletingLastPathComponent() == root,
                  name.hasPrefix(".backup-export-"),
                  name.hasSuffix(".json") else {
                throw BackupExportServiceError.cleanupFailed
            }
            var information = stat()
            if Darwin.fstatat(
                directoryDescriptor,
                name,
                &information,
                AT_SYMLINK_NOFOLLOW
            ) != 0 {
                guard errno == ENOENT else {
                    throw BackupExportServiceError.cleanupFailed
                }
                continue
            }
            guard (information.st_mode & S_IFMT) == S_IFREG,
                  information.st_nlink == 1,
                  UInt64(information.st_dev) == source.device,
                  UInt64(information.st_ino) == source.inode,
                  Darwin.unlinkat(directoryDescriptor, name, 0) == 0 else {
                throw BackupExportServiceError.cleanupFailed
            }
        }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw BackupExportServiceError.cleanupFailed
        }
    }

    func removeOwnedPublishedArchive(
        _ url: URL,
        within destinationDirectoryURL: URL
    ) throws {
        let value = url.standardizedFileURL
        let parentURL = destinationDirectoryURL.standardizedFileURL
        guard value.deletingLastPathComponent() == parentURL,
              value.lastPathComponent == "AssetRounds.fieldrecordbackup",
              try itemType(at: value) == .regular,
              try StreamingArchiveService.hasFormatMagic(at: value) else {
            throw BackupExportServiceError.cleanupFailed
        }
        let parent = Darwin.open(
            parentURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parent >= 0,
              Darwin.unlinkat(parent, value.lastPathComponent, 0) == 0,
              Darwin.fsync(parent) == 0 else {
            if parent >= 0 { _ = Darwin.close(parent) }
            throw BackupExportServiceError.cleanupFailed
        }
        _ = Darwin.close(parent)
    }

    func mapStreamingExportError(_ error: Error) -> BackupExportServiceError {
        if error is GenerationLeaseRegistryFailureV1 {
            return .generationLeaseLost
        }
        if let typed = error as? BackupExportServiceError { return typed }
        if let storage = error as? StoragePreflightError {
            if case .insufficientCapacity = storage { return .insufficientStorage }
            return .writeFailed
        }
        guard let failure = error as? StreamingArchiveFailureV1 else {
            return .writeFailed
        }
        switch failure {
        case .cancelled:
            return .cancelled
        case .insufficientStorage:
            return .insufficientStorage
        case .sourceChanged, .contentMismatch:
            return .sourceChanged
        case .cleanupFailed:
            return .cleanupFailed
        case .destinationExists:
            return .destinationExists
        default:
            return .writeFailed
        }
    }

    func validateGenerationLease() throws {
        do {
            try generationLeaseValidation()
        } catch {
            throw BackupExportServiceError.generationLeaseLost
        }
    }

    func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }

    func dtoOrder<T>(_ lhs: T, _ rhs: T) -> Bool where T: Identifiable, T.ID == UUID {
        uuid(lhs.id) < uuid(rhs.id)
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
                guard seen.insert(current).inserted, let row = byID[current] else {
                    throw BackupExportServiceError.invalidAuthority
                }
                cursor = row[keyPath: next]
            }
        }
    }
}

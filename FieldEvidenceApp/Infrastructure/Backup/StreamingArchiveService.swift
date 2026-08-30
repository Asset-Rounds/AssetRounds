import CryptoKit
import Darwin
import Foundation

enum C34SceneNavigationStreamingArchiveBoundaryV1 {
    static func validate() throws {
        guard C34SceneNavigationDeviceLifecycleBoundaryV1.validate() else {
            throw SceneNavigationFailureV1.invalidSnapshot
        }
    }
}

enum C50IncumbentFileExchangeStreamingArchiveServiceBoundaryV1 {
    static let routesAdapterFilesThroughBackupArchiveWriter = false
    static let routesBackupArchiveMembersThroughAdapterParser = false
    static let materializesAdapterScratchOnRestore = false
    static let unknownAdapterShapedArchiveMembersFailClosed = true
}

enum GuidedSurveyStreamingArchiveDispositionV1 {
    static func validate(records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion < 24 ||
                ((24...C49BackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) &&
                 records.guidedSurveys.count <= 200_000) else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        if records.recordsSchemaVersion >= AssetLocatorStreamingArchivePolicyV1.recordsSchemaVersion {
            do {
                try AssetLocatorStreamingArchivePolicyV1.validate(records: records)
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
        if records.recordsSchemaVersion >= ScheduleStreamingArchivePolicyV1.recordsSchemaVersion {
            do {
                try ScheduleStreamingArchivePolicyV1.validate(records: records)
                guard C51ScheduleBackupClosureV1.validatesEnvelope(records.schedules),
                      ScheduleStreamingArchivePolicyV1.interruptionResumesAtCanonicalRecordBoundary,
                      !ScheduleStreamingArchivePolicyV1.partialClosureMayPublish else {
                    throw StreamingArchiveFailureV1.invalidArchive
                }
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
        if records.recordsSchemaVersion >= PlanStreamingArchivePolicyV1.recordsSchemaVersion {
            do {
                try PlanStreamingArchivePolicyV1.validate(records: records)
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
        if records.recordsSchemaVersion >= PlacementPoseStreamingArchivePolicyV1.recordsSchemaVersion {
            do {
                try PlacementPoseStreamingArchivePolicyV1.validate(records: records)
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
        if records.recordsSchemaVersion >= 30 {
            do {
                try C31LightingStreamingArchivePolicyV1.validate(records: records)
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
        if records.recordsSchemaVersion >= C32AssistanceStreamingArchivePolicyV1.recordsSchemaVersion {
            do {
                try C32AssistanceStreamingArchivePolicyV1.validate(records: records)
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
        if records.recordsSchemaVersion >= C47ActivityContractStreamingArchiveBoundaryV2.recordsSchemaVersion {
            do {
                try C47ActivityContractStreamingArchiveBoundaryV2.validate(records: records)
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
        if records.recordsSchemaVersion >= C49WorkResourceStreamingArchiveBoundaryV1.recordsSchemaVersion {
            do {
                try C49WorkResourceStreamingArchiveBoundaryV1.validate(records: records)
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
    }
}

/// Value-only archive worker. The synchronous entry points remain for released
/// callers; resumable jobs use the async variants so byte work never inherits
/// the UI actor.
struct StreamingArchiveService: Sendable {
    private struct CreatedExtraction {
        let parentDescriptor: Int32
        let rootDescriptor: Int32
        let rootName: String
        let rootURL: URL
        let rootSnapshot: StreamingArchiveSourceSnapshotV1
        var files: [String]
        var directories: [String]
    }

    private let limits: StreamingArchiveLimitsV1
    private let pathProfile:StreamingArchivePathProfileV1
    private let makeOperationID: @Sendable () -> UUID

    init(
        limits: StreamingArchiveLimitsV1 = .card17,
        pathProfile:StreamingArchivePathProfileV1 = .backupV4,
        makeOperationID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.limits = limits
        self.pathProfile=pathProfile
        self.makeOperationID = makeOperationID
    }

    static func hasFormatMagic(at archiveURL: URL) throws -> Bool {
        guard archiveURL.isFileURL else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        let descriptor = Darwin.open(
            archiveURL.standardizedFileURL.path,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw mapOpenFailure()
        }
        defer { Darwin.close(descriptor) }
        _ = try snapshotRegularFile(descriptor)
        let prefix = try readExactly(
            descriptor: descriptor,
            byteCount: StreamingArchiveFormatV1.magic.count
        )
        return StreamingArchiveFormatV1.hasMagic(prefix)
    }

    static func hasFormatMagicOffMain(at archiveURL: URL) async throws -> Bool {
        try await BackupOffMainWorkV1.run {
            try hasFormatMagic(at: archiveURL)
        }
    }

    func writeOffMain(
        _ plan: StreamingArchiveWritePlanV1,
        to destinationURL: URL,
        context: ResumableLocalJobExecutionContextV1? = nil,
        storageCheck: @escaping @Sendable (Int64) throws -> Void = { _ in }
    ) async throws -> StreamingArchiveWriteReceiptV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let taskContext = context
        return try await BackupOffMainWorkV1.run {
            try self.write(
                plan,
                to: destinationURL,
                cancellation: StreamingArchiveCancellationV1 {
                    guard !Task.isCancelled else {
                        throw StreamingArchiveFailureV1.cancelled
                    }
                    try taskContext?.validateGenerationLease()
                },
                storageCheck: storageCheck
            )
        }
    }

    func write(
        _ plan: StreamingArchiveWritePlanV1,
        to destinationURL: URL,
        cancellation: StreamingArchiveCancellationV1 = .none,
        storageCheck: (Int64) throws -> Void = { _ in }
    ) throws -> StreamingArchiveWriteReceiptV1 {
        try C34SceneNavigationStreamingArchiveBoundaryV1.validate()
        try limits.validate()
        try cancellation.checkpoint()
        try validateArchiveExtension(destinationURL, writing: true)
        let ordered = try validateWritePlan(plan)
        var expectedPayloadBytes: Int64 = 0
        for entry in ordered {
            expectedPayloadBytes = try Self.adding(
                expectedPayloadBytes,
                entry.expectedUncompressedByteCount,
                maximum: min(
                    limits.maximumStoredAggregateByteCount,
                    limits.maximumUncompressedAggregateByteCount
                ),
                failure: .uncompressedLimitExceeded
            )
        }
        let stagedAndPublished = try Self.adding(
            expectedPayloadBytes,
            expectedPayloadBytes,
            maximum: Int64.max,
            failure: .storedLimitExceeded
        )
        let withIndex = try Self.adding(
            stagedAndPublished,
            Int64(limits.maximumIndexByteCount),
            maximum: Int64.max,
            failure: .storedLimitExceeded
        )
        let requiredStorage = try Self.adding(
            withIndex,
            limits.stagingReserveByteCount,
            maximum: Int64.max,
            failure: .storedLimitExceeded
        )
        do { try storageCheck(requiredStorage) }
        catch { throw Self.map(error) }
        let stagingRoot = plan.stagingDirectoryURL.standardizedFileURL
        let stagingRootDescriptor = try openDirectory(stagingRoot)
        defer { Darwin.close(stagingRootDescriptor) }
        let stagingRootSnapshot = try snapshotDirectory(stagingRootDescriptor)
        try ProtectedFilePolicyV1.verify(.stagingDirectory, at: stagingRoot) {
            guard try Self.snapshotDirectory(stagingRootDescriptor)
                == stagingRootSnapshot else {
                throw StreamingArchiveFailureV1.sourceChanged
            }
        }

        let operationName = "archive-\(canonical(makeOperationID()))"
        guard Darwin.mkdirat(stagingRootDescriptor, operationName, 0o700) == 0 else {
            throw mapWriteFailure()
        }
        let operationURL = stagingRoot.appendingPathComponent(
            operationName,
            isDirectory: true
        )
        let operationDescriptor = Darwin.openat(
            stagingRootDescriptor,
            operationName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard operationDescriptor >= 0 else {
            _ = Darwin.unlinkat(stagingRootDescriptor, operationName, AT_REMOVEDIR)
            throw mapOpenFailure()
        }
        let operationSnapshot: StreamingArchiveSourceSnapshotV1
        do {
            operationSnapshot = try Self.snapshotDirectory(operationDescriptor)
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                at: operationURL
            ) {
                guard try Self.snapshotDirectory(operationDescriptor)
                    == operationSnapshot,
                      Self.sameIdentity(
                        try Self.snapshotDirectory(stagingRootDescriptor),
                        stagingRootSnapshot
                      ) else {
                    throw StreamingArchiveFailureV1.sourceChanged
                }
            }
        } catch {
            Darwin.close(operationDescriptor)
            _ = Darwin.unlinkat(stagingRootDescriptor, operationName, AT_REMOVEDIR)
            throw map(error)
        }

        var stagedNames: [String] = []
        var operationDescriptorIsOpen = true
        var operationDirectoryExists = true
        var destinationParentDescriptor: Int32?
        var temporaryPublication: (parent: Int32, name: String, snapshot: StreamingArchiveSourceSnapshotV1?)?
        var published: (parent: Int32, name: String, snapshot: StreamingArchiveSourceSnapshotV1)?
        do {
            var indexEntries: [StreamingArchiveEntryV1] = []
            var storedTotal: Int64 = 0
            var uncompressedTotal: Int64 = 0
            for (offset, entry) in ordered.enumerated() {
                try cancellation.checkpoint()
                guard entry.compression == .stored else {
                    throw StreamingArchiveFailureV1.invalidPlan
                }
                let stagedName = String(format: "entry-%08d.payload", offset)
                let stagedURL = operationURL.appendingPathComponent(stagedName)
                let stagedDescriptor = Darwin.openat(
                    operationDescriptor,
                    stagedName,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                    0o600
                )
                guard stagedDescriptor >= 0 else { throw mapWriteFailure() }
                stagedNames.append(stagedName)
                do {
                    let stagedSnapshot = try Self.snapshotRegularFile(stagedDescriptor)
                    try ProtectedFilePolicyV1.applyAndVerify(
                        .stagingFile,
                        at: stagedURL
                    ) {
                        guard try Self.snapshotRegularFile(stagedDescriptor)
                            == stagedSnapshot else {
                            throw StreamingArchiveFailureV1.sourceChanged
                        }
                    }
                    let result = try copySource(
                        entry,
                        to: stagedDescriptor,
                        cancellation: cancellation
                    )
                    guard Darwin.fsync(stagedDescriptor) == 0 else {
                        throw mapWriteFailure()
                    }
                    guard result.byteCount == entry.expectedUncompressedByteCount,
                          result.sha256 == entry.expectedContentSHA256 else {
                        throw StreamingArchiveFailureV1.contentMismatch
                    }
                    try ProtectedFilePolicyV1.verify(.stagingFile, at: stagedURL) {
                        let after = try Self.snapshotRegularFile(stagedDescriptor)
                        guard after.device == stagedSnapshot.device,
                              after.inode == stagedSnapshot.inode,
                              after.linkCount == 1,
                              after.byteCount == result.byteCount else {
                            throw StreamingArchiveFailureV1.sourceChanged
                        }
                    }
                    storedTotal = try adding(
                        storedTotal,
                        result.byteCount,
                        maximum: limits.maximumStoredAggregateByteCount,
                        failure: .storedLimitExceeded
                    )
                    uncompressedTotal = try adding(
                        uncompressedTotal,
                        result.byteCount,
                        maximum: limits.maximumUncompressedAggregateByteCount,
                        failure: .uncompressedLimitExceeded
                    )
                    indexEntries.append(StreamingArchiveEntryV1(
                        path: entry.path,
                        mimeType: entry.mimeType,
                        compression: .stored,
                        storedByteCount: result.byteCount,
                        uncompressedByteCount: result.byteCount,
                        storedSHA256: result.sha256,
                        contentSHA256: result.sha256
                    ))
                } catch {
                    Darwin.close(stagedDescriptor)
                    throw error
                }
                Darwin.close(stagedDescriptor)
            }
            guard Darwin.fsync(operationDescriptor) == 0 else {
                throw mapWriteFailure()
            }

            let index = StreamingArchiveIndexV1(
                archiveSchemaVersion: StreamingArchiveIndexV1.currentSchemaVersion,
                entries: indexEntries,
                storedPayloadByteCount: storedTotal,
                uncompressedPayloadByteCount: uncompressedTotal
            )
            let indexData = try canonicalIndexData(index)
            guard indexData.count <= limits.maximumIndexByteCount else {
                throw StreamingArchiveFailureV1.entryLimitExceeded
            }
            let header = makeHeader(
                indexByteCount: Int64(indexData.count),
                indexDigest: Data(SHA256.hash(data: indexData))
            )

            let destination = destinationURL.standardizedFileURL
            guard destinationURL.isFileURL,
                  validLeaf(destination.lastPathComponent) else {
                throw StreamingArchiveFailureV1.invalidDestination
            }
            let destinationParentURL = destination.deletingLastPathComponent()
            let destinationParent = try Self.openDirectory(destinationParentURL)
            destinationParentDescriptor = destinationParent
            guard !existsNoFollow(
                parent: destinationParent,
                name: destination.lastPathComponent
            ) else {
                throw StreamingArchiveFailureV1.destinationExists
            }
            let temporaryName = ".\(destination.lastPathComponent).\(canonical(makeOperationID())).tmp"
            let destinationDescriptor = Darwin.openat(
                destinationParent,
                temporaryName,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                0o600
            )
            guard destinationDescriptor >= 0 else { throw mapWriteFailure() }
            temporaryPublication = (destinationParent, temporaryName, nil)
            var archiveHasher = SHA256()
            let finalTemporarySnapshot: StreamingArchiveSourceSnapshotV1
            do {
                let temporarySnapshot = try Self.snapshotRegularFile(
                    destinationDescriptor
                )
                temporaryPublication = (
                    destinationParent,
                    temporaryName,
                    temporarySnapshot
                )
                try writeAll(header, to: destinationDescriptor)
                archiveHasher.update(data: header)
                try writeAll(indexData, to: destinationDescriptor)
                archiveHasher.update(data: indexData)
                for (stagedName, expectedEntry) in zip(stagedNames, index.entries) {
                    try cancellation.checkpoint()
                    let stagedDescriptor = Darwin.openat(
                        operationDescriptor,
                        stagedName,
                        O_RDONLY | O_NOFOLLOW
                    )
                    guard stagedDescriptor >= 0 else { throw mapOpenFailure() }
                    do {
                        let stagedBefore = try Self.snapshotRegularFile(stagedDescriptor)
                        guard stagedBefore.byteCount == expectedEntry.storedByteCount else {
                            throw StreamingArchiveFailureV1.contentMismatch
                        }
                        var stagedHasher = SHA256()
                        try streamCopy(
                            from: stagedDescriptor,
                            to: destinationDescriptor,
                            expectedByteCount: stagedBefore.byteCount,
                            hasher: &archiveHasher,
                            secondHasher: &stagedHasher,
                            cancellation: cancellation
                        )
                        guard try Self.snapshotRegularFile(stagedDescriptor) == stagedBefore,
                              hex(stagedHasher.finalize())
                                == expectedEntry.storedSHA256 else {
                            throw StreamingArchiveFailureV1.contentMismatch
                        }
                    } catch {
                        Darwin.close(stagedDescriptor)
                        throw error
                    }
                    Darwin.close(stagedDescriptor)
                }
                guard Darwin.fsync(destinationDescriptor) == 0 else {
                    throw mapWriteFailure()
                }
                finalTemporarySnapshot = try Self.snapshotRegularFile(
                    destinationDescriptor
                )
                guard finalTemporarySnapshot.device == temporarySnapshot.device,
                      finalTemporarySnapshot.inode == temporarySnapshot.inode,
                      finalTemporarySnapshot.linkCount == 1 else {
                    throw StreamingArchiveFailureV1.sourceChanged
                }
                temporaryPublication = (
                    destinationParent,
                    temporaryName,
                    finalTemporarySnapshot
                )
            } catch {
                Darwin.close(destinationDescriptor)
                throw error
            }
            Darwin.close(destinationDescriptor)
            let archiveDigest = hex(archiveHasher.finalize())

            try removeStagedFiles(
                stagedNames,
                operationDescriptor: operationDescriptor
            )
            stagedNames.removeAll()
            guard Darwin.close(operationDescriptor) == 0 else {
                operationDescriptorIsOpen = false
                throw StreamingArchiveFailureV1.cleanupFailed
            }
            operationDescriptorIsOpen = false
            guard Darwin.unlinkat(
                    stagingRootDescriptor,
                    operationName,
                    AT_REMOVEDIR
                  ) == 0 else {
                throw StreamingArchiveFailureV1.cleanupFailed
            }
            operationDirectoryExists = false
            guard Darwin.fsync(stagingRootDescriptor) == 0 else {
                throw StreamingArchiveFailureV1.cleanupFailed
            }

            try cancellation.checkpoint()
            guard Darwin.renameatx_np(
                destinationParent,
                temporaryName,
                destinationParent,
                destination.lastPathComponent,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                if errno == EEXIST { throw StreamingArchiveFailureV1.destinationExists }
                throw mapWriteFailure()
            }
            temporaryPublication = nil
            published = (
                destinationParent,
                destination.lastPathComponent,
                finalTemporarySnapshot
            )
            guard Darwin.fsync(destinationParent) == 0 else {
                if identityMatches(
                    parent: destinationParent,
                    name: destination.lastPathComponent,
                    snapshot: finalTemporarySnapshot
                ), Darwin.unlinkat(
                    destinationParent,
                    destination.lastPathComponent,
                    0
                ) == 0, Darwin.fsync(destinationParent) == 0 {
                    throw mapWriteFailure()
                }
                throw StreamingArchiveFailureV1.cleanupFailed
            }
            published = nil
            Darwin.close(destinationParent)
            destinationParentDescriptor = nil
            let archiveByteCount = try adding(
                Int64(header.count),
                try adding(
                    Int64(indexData.count),
                    storedTotal,
                    maximum: Int64.max,
                    failure: .storedLimitExceeded
                ),
                maximum: Int64.max,
                failure: .storedLimitExceeded
            )
            return StreamingArchiveWriteReceiptV1(
                archiveURL: destination,
                archiveByteCount: archiveByteCount,
                archiveSHA256: archiveDigest,
                index: index
            )
        } catch {
            var cleanupSucceeded = true
            if let temporaryPublication {
                if !Self.unlinkCreatedFile(
                    parent: temporaryPublication.parent,
                    name: temporaryPublication.name,
                    snapshot: temporaryPublication.snapshot
                ) { cleanupSucceeded = false }
            }
            if let published,
               identityMatches(
                parent: published.parent,
                name: published.name,
                snapshot: published.snapshot
               ) {
                if Darwin.unlinkat(published.parent, published.name, 0) != 0
                    || Darwin.fsync(published.parent) != 0 {
                    cleanupSucceeded = false
                }
            } else if published != nil {
                cleanupSucceeded = false
            }
            if let destinationParentDescriptor {
                if Darwin.close(destinationParentDescriptor) != 0 {
                    cleanupSucceeded = false
                }
            }
            if operationDescriptorIsOpen {
                do {
                    try removeStagedFiles(
                        stagedNames,
                        operationDescriptor: operationDescriptor
                    )
                } catch {
                    cleanupSucceeded = false
                }
                if Darwin.close(operationDescriptor) != 0 {
                    cleanupSucceeded = false
                }
                operationDescriptorIsOpen = false
            }
            if operationDirectoryExists {
                if Darwin.unlinkat(
                    stagingRootDescriptor,
                    operationName,
                    AT_REMOVEDIR
                ) != 0 || Darwin.fsync(stagingRootDescriptor) != 0 {
                    cleanupSucceeded = false
                }
            }
            if !cleanupSucceeded {
                throw StreamingArchiveFailureV1.cleanupFailed
            }
            if error is GenerationLeaseRegistryFailureV1 || error is CancellationError {
                throw error
            }
            throw map(error)
        }
    }

    func extract(
        _ archiveURL: URL,
        to extractedDirectoryURL: URL,
        cancellation: StreamingArchiveCancellationV1 = .none,
        storageCheck: (Int64) throws -> Void = { _ in }
    ) throws -> StreamingArchiveExtractionV1 {
        try limits.validate()
        try cancellation.checkpoint()
        guard archiveURL.isFileURL, extractedDirectoryURL.isFileURL else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        try validateArchiveExtension(archiveURL, writing: false)
        let archive = archiveURL.standardizedFileURL
        let archiveDescriptor = Darwin.open(archive.path, O_RDONLY | O_NOFOLLOW)
        guard archiveDescriptor >= 0 else { throw Self.mapOpenFailure() }
        defer { Darwin.close(archiveDescriptor) }
        let before = try Self.snapshotRegularFile(archiveDescriptor)
        var archiveHasher = SHA256()
        let header = try Self.readExactly(
            descriptor: archiveDescriptor,
            byteCount: StreamingArchiveFormatV1.headerByteCount
        )
        archiveHasher.update(data: header)
        let headerValues = try parseHeader(header)
        guard headerValues.indexByteCount <= Int64(limits.maximumIndexByteCount) else {
            throw StreamingArchiveFailureV1.entryLimitExceeded
        }
        let indexData = try Self.readExactly(
            descriptor: archiveDescriptor,
            byteCount: Int(headerValues.indexByteCount)
        )
        archiveHasher.update(data: indexData)
        guard Data(SHA256.hash(data: indexData)) == headerValues.indexDigest else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        let index = try decodeCanonicalIndex(indexData)
        try validateIndex(index)
        if pathProfile == .surveyTemplate{try SurveyTemplateArchiveAdmissionV1.validate(index)}
        if pathProfile == .portableReviewRequest {
            try PortableReviewRequestArchiveAdmissionV1.validate(index)
        }
        let expectedArchiveBytes = try adding(
            Int64(StreamingArchiveFormatV1.headerByteCount),
            try adding(
                headerValues.indexByteCount,
                index.storedPayloadByteCount,
                maximum: Int64.max,
                failure: .invalidArchive
            ),
            maximum: Int64.max,
            failure: .invalidArchive
        )
        guard before.byteCount == expectedArchiveBytes else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        let requiredStorage = try adding(
            index.uncompressedPayloadByteCount,
            limits.stagingReserveByteCount,
            maximum: Int64.max,
            failure: .uncompressedLimitExceeded
        )
        do { try storageCheck(requiredStorage) }
        catch { throw map(error) }

        var created = try createExtractionRoot(extractedDirectoryURL)
        do {
            for entry in index.entries {
                try cancellation.checkpoint()
                guard entry.compression == .stored else {
                    throw StreamingArchiveFailureV1.unsupportedFormat
                }
                try ensureParentDirectory(
                    for: entry.path,
                    extraction: &created
                )
                let components = entry.path.split(separator: "/").map(String.init)
                let parentRelative = components.dropLast().joined(separator: "/")
                let parentDescriptor = try openRelativeDirectory(
                    parentRelative,
                    rootDescriptor: created.rootDescriptor
                )
                defer { Darwin.close(parentDescriptor) }
                guard let leaf = components.last else {
                    throw StreamingArchiveFailureV1.hostilePath
                }
                let outputDescriptor = Darwin.openat(
                    parentDescriptor,
                    leaf,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                    0o600
                )
                guard outputDescriptor >= 0 else { throw mapWriteFailure() }
                created.files.append(entry.path)
                let outputURL = created.rootURL.appendingPathComponent(entry.path)
                do {
                    let initialOutput = try Self.snapshotRegularFile(
                        outputDescriptor
                    )
                    try ProtectedFilePolicyV1.applyAndVerify(
                        .stagingFile,
                        at: outputURL
                    ) {
                        guard try Self.snapshotRegularFile(outputDescriptor)
                            == initialOutput else {
                            throw StreamingArchiveFailureV1.sourceChanged
                        }
                    }
                    var contentHasher = SHA256()
                    try streamCopy(
                        from: archiveDescriptor,
                        to: outputDescriptor,
                        expectedByteCount: entry.storedByteCount,
                        hasher: &archiveHasher,
                        secondHasher: &contentHasher,
                        cancellation: cancellation
                    )
                    guard Darwin.fsync(outputDescriptor) == 0 else {
                        throw mapWriteFailure()
                    }
                    let digest = hex(contentHasher.finalize())
                    let afterOutput = try Self.snapshotRegularFile(outputDescriptor)
                    guard digest == entry.storedSHA256,
                          digest == entry.contentSHA256,
                          afterOutput.device == initialOutput.device,
                          afterOutput.inode == initialOutput.inode,
                          afterOutput.linkCount == 1,
                          afterOutput.byteCount == entry.uncompressedByteCount else {
                        throw StreamingArchiveFailureV1.contentMismatch
                    }
                    try ProtectedFilePolicyV1.verify(.stagingFile, at: outputURL) {
                        let current = try Self.snapshotRegularFile(outputDescriptor)
                        guard current == afterOutput else {
                            throw StreamingArchiveFailureV1.sourceChanged
                        }
                    }
                } catch {
                    Darwin.close(outputDescriptor)
                    throw error
                }
                Darwin.close(outputDescriptor)
                guard Darwin.fsync(parentDescriptor) == 0 else {
                    throw mapWriteFailure()
                }
            }
            let after = try Self.snapshotRegularFile(archiveDescriptor)
            guard after == before else {
                throw StreamingArchiveFailureV1.sourceChanged
            }
            try cancellation.checkpoint()
            guard Darwin.fsync(created.rootDescriptor) == 0,
                  Darwin.fsync(created.parentDescriptor) == 0 else {
                throw mapWriteFailure()
            }
            let digest = hex(archiveHasher.finalize())
            Darwin.close(created.rootDescriptor)
            Darwin.close(created.parentDescriptor)
            return StreamingArchiveExtractionV1(
                archiveURL: archive,
                extractedDirectoryURL: created.rootURL,
                archiveSHA256: digest,
                index: index
            )
        } catch {
            let cleaned = cleanupExtraction(&created)
            guard cleaned else { throw StreamingArchiveFailureV1.cleanupFailed }
            if error is GenerationLeaseRegistryFailureV1 || error is CancellationError {
                throw error
            }
            throw map(error)
        }
    }

    func extractOffMain(
        _ archiveURL: URL,
        to extractedDirectoryURL: URL,
        context: ResumableLocalJobExecutionContextV1? = nil,
        storageCheck: @escaping @Sendable (Int64) throws -> Void = { _ in }
    ) async throws -> StreamingArchiveExtractionV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let taskContext = context
        return try await BackupOffMainWorkV1.run {
            try self.extract(
                archiveURL,
                to: extractedDirectoryURL,
                cancellation: StreamingArchiveCancellationV1 {
                    guard !Task.isCancelled else {
                        throw StreamingArchiveFailureV1.cancelled
                    }
                    try taskContext?.validateGenerationLease()
                },
                storageCheck: storageCheck
            )
        }
    }

    func extractSurveyTemplateFromQuarantineOffMain(_ archiveURL:URL,quarantineRootURL:URL,to extractedDirectoryURL:URL,context:ResumableLocalJobExecutionContextV1?=nil,storageCheck:@escaping @Sendable(Int64)throws->Void={_ in})async throws->StreamingArchiveExtractionV1{
        guard pathProfile == .surveyTemplate,archiveURL.isFileURL,quarantineRootURL.isFileURL else{throw StreamingArchiveFailureV1.invalidPlan}
        let archive=archiveURL.standardizedFileURL,root=quarantineRootURL.standardizedFileURL,rootPrefix=root.path.hasSuffix("/") ? root.path:root.path+"/"
        guard archive.path.hasPrefix(rootPrefix),archive.pathExtension==SurveyTemplateArchiveManifestV1.fileExtension else{throw StreamingArchiveFailureV1.invalidArchive}
        let value=try await extractOffMain(archive,to:extractedDirectoryURL,context:context,storageCheck:storageCheck);try SurveyTemplateArchiveAdmissionV1.validate(value.index);return value
    }
}

private actor BackupOffMainWorkerV1 {
    static let shared = BackupOffMainWorkerV1()

    func run<Value: Sendable>(
        _ operation: @Sendable () throws -> Value
    ) throws -> Value {
        try Task.checkCancellation()
        return try operation()
    }
}

enum BackupOffMainWorkV1 {
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        do {
            return try await BackupOffMainWorkerV1.shared.run(operation)
        } catch let failure as StreamingArchiveFailureV1
            where failure == .cancelled {
            throw CancellationError()
        }
    }
}

enum C30EvidenceContextStreamingArchiveServiceV1 {
    static let archivesCanonicalContextRows = true
    static let rebuildsDerivedPairProjection = true
    static let rejectsCrossWorkspaceRows = true
    static let sourceBytesRemainImmutable = true

    static func validate(_ records: [V30BackupEvidenceContextRecordV1]) throws {
        guard archivesCanonicalContextRows, rebuildsDerivedPairProjection,
              rejectsCrossWorkspaceRows, sourceBytesRemainImmutable else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        try C30EvidenceContextStreamingArchivePolicyV1.validate(records: records)
    }
}

enum C31LightingStreamingArchiveServiceV1 {
    static let archivesCanonicalLightingRows = true
    static let rebuildsDerivedLightingProjection = true
    static let rejectsCrossWorkspaceRows = true
    static let sourceBytesRemainImmutable = true
    static let licensedCriterionTextIncluded = false

    static func validate(_ records: V4BackupRecordsV1) throws {
        guard archivesCanonicalLightingRows,
              rebuildsDerivedLightingProjection,
              rejectsCrossWorkspaceRows,
              sourceBytesRemainImmutable,
              !licensedCriterionTextIncluded else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        try C31LightingStreamingArchivePolicyV1.validate(records: records)
    }
}

private extension StreamingArchiveService {
    static func canonical(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    func validateWritePlan(
        _ plan: StreamingArchiveWritePlanV1
    ) throws -> [StreamingArchiveWriteEntryV1] {
        guard plan.stagingDirectoryURL.isFileURL,
              !plan.entries.isEmpty,
              plan.entries.count <= limits.maximumEntryCount else {
            throw StreamingArchiveFailureV1.invalidPlan
        }
        let ordered = plan.entries.sorted { utf8Less($0.path, $1.path) }
        var paths = Set<String>()
        var folded = Set<String>()
        var aggregate: Int64 = 0
        for entry in ordered {
            try validatePathAndMIME(entry.path, mimeType: entry.mimeType)
            guard entry.sourceRootURL.isFileURL,
                  validSourceRelativePath(entry.sourceRelativePath),
                  entry.compression == .stored,
                  entry.expectedUncompressedByteCount >= 0,
                  entry.expectedUncompressedByteCount
                    <= limits.maximumUncompressedEntryByteCount,
                  entry.expectedUncompressedByteCount
                    <= limits.maximumStoredEntryByteCount,
                  lowercaseSHA256(entry.expectedContentSHA256) else {
                throw StreamingArchiveFailureV1.invalidPlan
            }
            guard paths.insert(entry.path).inserted,
                  folded.insert(collisionKey(entry.path)).inserted else {
                throw StreamingArchiveFailureV1.duplicatePath
            }
            aggregate = try adding(
                aggregate,
                entry.expectedUncompressedByteCount,
                maximum: min(
                    limits.maximumStoredAggregateByteCount,
                    limits.maximumUncompressedAggregateByteCount
                ),
                failure: .uncompressedLimitExceeded
            )
        }
        if pathProfile == .portableReviewRequest {
            try PortableReviewRequestArchiveAdmissionV1.validateDeclaredEntries(
                ordered.map {
                    ($0.path, $0.mimeType, $0.expectedUncompressedByteCount)
                }
            )
        }
        return ordered
    }

    func validateIndex(_ index: StreamingArchiveIndexV1) throws {
        guard index.archiveSchemaVersion
                == StreamingArchiveIndexV1.currentSchemaVersion,
              !index.entries.isEmpty,
              index.entries.count <= limits.maximumEntryCount else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        let sorted = index.entries.sorted { utf8Less($0.path, $1.path) }
        guard sorted == index.entries else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        var paths = Set<String>()
        var folded = Set<String>()
        var stored: Int64 = 0
        var uncompressed: Int64 = 0
        for entry in index.entries {
            try validatePathAndMIME(entry.path, mimeType: entry.mimeType)
            guard paths.insert(entry.path).inserted,
                  folded.insert(collisionKey(entry.path)).inserted else {
                throw StreamingArchiveFailureV1.duplicatePath
            }
            guard entry.compression == .stored else {
                throw StreamingArchiveFailureV1.unsupportedFormat
            }
            guard entry.storedByteCount >= 0,
                  entry.uncompressedByteCount >= 0,
                  entry.storedByteCount <= limits.maximumStoredEntryByteCount,
                  entry.uncompressedByteCount
                    <= limits.maximumUncompressedEntryByteCount,
                  entry.storedByteCount == entry.uncompressedByteCount,
                  lowercaseSHA256(entry.storedSHA256),
                  lowercaseSHA256(entry.contentSHA256) else {
                throw StreamingArchiveFailureV1.invalidArchive
            }
            stored = try adding(
                stored,
                entry.storedByteCount,
                maximum: limits.maximumStoredAggregateByteCount,
                failure: .storedLimitExceeded
            )
            uncompressed = try adding(
                uncompressed,
                entry.uncompressedByteCount,
                maximum: limits.maximumUncompressedAggregateByteCount,
                failure: .uncompressedLimitExceeded
            )
        }
        guard stored == index.storedPayloadByteCount,
              uncompressed == index.uncompressedPayloadByteCount else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
    }

    func validatePathAndMIME(_ path: String, mimeType: String) throws {
        guard path == path.precomposedStringWithCanonicalMapping,
              !path.isEmpty,
              path.utf8.count <= limits.maximumPathUTF8ByteCount,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: {
                $0.value == 0 || $0.value < 0x20 || $0.value == 0x7f
              }) else {
            throw StreamingArchiveFailureV1.hostilePath
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        let maximumDepth = pathProfile == .surveyTemplate
            ? SurveyTemplateArchiveAdmissionV1.maximumDepth
            : (pathProfile == .portableReviewRequest
                ? PortableReviewRequestArchiveAdmissionV1.maximumDepth : 2)
        guard !components.isEmpty,
              components.count <= maximumDepth,
              components.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".."
                    && $0 == $0.precomposedStringWithCanonicalMapping
              }) else {
            throw StreamingArchiveFailureV1.hostilePath
        }
        let valid: Bool
        if pathProfile == .surveyTemplate {
            valid=ContentContractValidationV1.validMediaType(mimeType)
        } else if pathProfile == .portableReviewRequest {
            switch components {
            case [let name] where PortableReviewRequestArchiveAdmissionV1.requiredEntries[name] != nil:
                valid = mimeType == PortableReviewRequestArchiveAdmissionV1.requiredEntries[name]
            case ["report", "report.pdf"]:
                valid = mimeType == "application/pdf"
            case ["report", "report.txt"]:
                valid = mimeType == "text/plain"
            case ["media", let name]:
                valid = canonicalUUIDLeaf(name, suffix: ".jpg")
                    && mimeType == "image/jpeg"
            default:
                valid = false
            }
        } else {switch components {
        case ["manifest.json"], ["records.json"]:
            valid = mimeType == "application/json"
        case ["review-exchange", "snapshot.json"]:
            valid = mimeType == PortableExchangeBackupMemberV2.mimeType
        case ["media", let name], ["thumbnails", let name]:
            valid = canonicalUUIDLeaf(name, suffix: ".jpg")
                && mimeType == "image/jpeg"
        case ["snapshots", let name]:
            valid = canonicalUUIDLeaf(name, suffix: ".json")
                && mimeType == "application/json"
        case ["pdfs", let name]:
            valid = canonicalUUIDLeaf(name, suffix: ".pdf")
                && mimeType == "application/pdf"
        default:
            valid = false
        }}
        guard valid else { throw StreamingArchiveFailureV1.hostilePath }
    }

    func validateArchiveExtension(_ url: URL, writing: Bool) throws {
        guard pathProfile == .portableReviewRequest else { return }
        guard url.isFileURL,
              url.pathExtension == PortableReviewRequestArchiveAdmissionV1.fileExtension else {
            throw writing
                ? StreamingArchiveFailureV1.invalidDestination
                : StreamingArchiveFailureV1.invalidArchive
        }
    }

    func copySource(
        _ entry: StreamingArchiveWriteEntryV1,
        to destinationDescriptor: Int32,
        cancellation: StreamingArchiveCancellationV1
    ) throws -> (byteCount: Int64, sha256: String) {
        let rootURL = entry.sourceRootURL.standardizedFileURL
        let rootDescriptor = try Self.openDirectory(rootURL)
        var retainedDescriptors = [rootDescriptor]
        defer {
            for descriptor in retainedDescriptors.reversed() {
                Darwin.close(descriptor)
            }
        }
        let rootBefore = try Self.snapshotDirectory(rootDescriptor)
        guard Self.matchesRootIdentity(
            rootBefore,
            entry.expectedSourceRootIdentity
        ) else {
            throw StreamingArchiveFailureV1.sourceChanged
        }
        let components = entry.sourceRelativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard let leaf = components.last else {
            throw StreamingArchiveFailureV1.invalidPlan
        }
        var parentDescriptor = rootDescriptor
        var ancestorSnapshots: [StreamingArchiveSourceSnapshotV1] = [rootBefore]
        for component in components.dropLast() {
            let next = Darwin.openat(
                parentDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard next >= 0 else { throw Self.mapOpenFailure() }
            retainedDescriptors.append(next)
            ancestorSnapshots.append(try Self.snapshotDirectory(next))
            parentDescriptor = next
        }
        let descriptor = Darwin.openat(
            parentDescriptor,
            leaf,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw Self.mapOpenFailure() }
        retainedDescriptors.append(descriptor)
        let before = try Self.snapshotRegularFile(descriptor)
        guard before.byteCount == entry.expectedUncompressedByteCount,
              before.byteCount <= limits.maximumUncompressedEntryByteCount else {
            throw StreamingArchiveFailureV1.sourceChanged
        }
        var hasher = SHA256()
        try streamCopy(
            from: descriptor,
            to: destinationDescriptor,
            expectedByteCount: before.byteCount,
            hasher: &hasher,
            cancellation: cancellation
        )
        let after = try Self.snapshotRegularFile(descriptor)
        guard after == before,
              retainedDescriptors.dropLast().enumerated().allSatisfy({ offset, value in
                guard let current = try? Self.snapshotDirectory(value) else {
                    return false
                }
                return Self.sameIdentity(current, ancestorSnapshots[offset])
              }) else {
            throw StreamingArchiveFailureV1.sourceChanged
        }
        let reopenedRoot = try Self.openDirectory(rootURL)
        defer { Darwin.close(reopenedRoot) }
        let reopenedRootSnapshot = try Self.snapshotDirectory(reopenedRoot)
        guard Self.sameIdentity(
            reopenedRootSnapshot,
            rootBefore
        ), Self.matchesRootIdentity(
            reopenedRootSnapshot,
            entry.expectedSourceRootIdentity
        ) else {
            throw StreamingArchiveFailureV1.sourceChanged
        }
        return (before.byteCount, hex(hasher.finalize()))
    }

    func streamCopy(
        from source: Int32,
        to destination: Int32,
        expectedByteCount: Int64,
        hasher: inout SHA256,
        secondHasher: inout SHA256,
        cancellation: StreamingArchiveCancellationV1
    ) throws {
        var remaining = expectedByteCount
        var buffer = [UInt8](repeating: 0, count: limits.bufferByteCount)
        while remaining > 0 {
            try cancellation.checkpoint()
            let requested = min(buffer.count, Int(remaining))
            let count = try Self.readSome(
                descriptor: source,
                buffer: &buffer,
                requested: requested
            )
            guard count > 0 else {
                throw StreamingArchiveFailureV1.contentMismatch
            }
            let data = Data(buffer[0..<count])
            hasher.update(data: data)
            secondHasher.update(data: data)
            try Self.writeAll(data, to: destination)
            remaining -= Int64(count)
        }
    }

    func streamCopy(
        from source: Int32,
        to destination: Int32,
        expectedByteCount: Int64,
        hasher: inout SHA256,
        cancellation: StreamingArchiveCancellationV1
    ) throws {
        var remaining = expectedByteCount
        var buffer = [UInt8](repeating: 0, count: limits.bufferByteCount)
        while remaining > 0 {
            try cancellation.checkpoint()
            let requested = min(buffer.count, Int(remaining))
            let count = try Self.readSome(
                descriptor: source,
                buffer: &buffer,
                requested: requested
            )
            guard count > 0 else {
                throw StreamingArchiveFailureV1.contentMismatch
            }
            let data = Data(buffer[0..<count])
            hasher.update(data: data)
            try Self.writeAll(data, to: destination)
            remaining -= Int64(count)
        }
    }

    func createExtractionRoot(_ url: URL) throws -> CreatedExtraction {
        let root = url.standardizedFileURL
        guard validLeaf(root.lastPathComponent) else {
            throw StreamingArchiveFailureV1.invalidDestination
        }
        let parent = try Self.openDirectory(root.deletingLastPathComponent())
        guard !Self.existsNoFollow(parent: parent, name: root.lastPathComponent),
              Darwin.mkdirat(parent, root.lastPathComponent, 0o700) == 0 else {
            Darwin.close(parent)
            throw StreamingArchiveFailureV1.destinationExists
        }
        let descriptor = Darwin.openat(
            parent,
            root.lastPathComponent,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            _ = Darwin.unlinkat(parent, root.lastPathComponent, AT_REMOVEDIR)
            Darwin.close(parent)
            throw Self.mapOpenFailure()
        }
        do {
            let snapshot = try Self.snapshotDirectory(descriptor)
            try ProtectedFilePolicyV1.applyAndVerify(.restoreStaging, at: root) {
                guard try Self.snapshotDirectory(descriptor) == snapshot else {
                    throw StreamingArchiveFailureV1.sourceChanged
                }
            }
            return CreatedExtraction(
                parentDescriptor: parent,
                rootDescriptor: descriptor,
                rootName: root.lastPathComponent,
                rootURL: root,
                rootSnapshot: snapshot,
                files: [],
                directories: []
            )
        } catch {
            Darwin.close(descriptor)
            _ = Darwin.unlinkat(parent, root.lastPathComponent, AT_REMOVEDIR)
            Darwin.close(parent)
            throw map(error)
        }
    }

    func ensureParentDirectory(
        for path: String,
        extraction: inout CreatedExtraction
    ) throws {
        let components=path.split(separator:"/").dropLast().map(String.init);guard !components.isEmpty else{return};var parent=Darwin.dup(extraction.rootDescriptor);guard parent>=0 else{throw Self.mapOpenFailure()};defer{Darwin.close(parent)};var relative=""
        for component in components{relative=relative.isEmpty ? component:"\(relative)/\(component)";if !extraction.directories.contains(relative){guard Darwin.mkdirat(parent,component,0o700)==0 else{throw Self.mapWriteFailure()};extraction.directories.append(relative)};let next=Darwin.openat(parent,component,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);guard next>=0 else{throw Self.mapOpenFailure()};Darwin.close(parent);parent=next;let url=extraction.rootURL.appendingPathComponent(relative,isDirectory:true),snapshot=try Self.snapshotDirectory(parent);try ProtectedFilePolicyV1.applyAndVerify(.restoreStaging,at:url){guard try Self.snapshotDirectory(parent)==snapshot else{throw StreamingArchiveFailureV1.sourceChanged}}}
        guard Darwin.fsync(extraction.rootDescriptor)==0 else{throw Self.mapWriteFailure()}
    }

    func cleanupExtraction(_ extraction: inout CreatedExtraction) -> Bool {
        var success = true
        for path in extraction.files.reversed() {
            let components = path.split(separator: "/").map(String.init)
            let parent: Int32
            if components.count == 2 {
                parent = Darwin.openat(
                    extraction.rootDescriptor,
                    components[0],
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
            } else {
                parent = Darwin.dup(extraction.rootDescriptor)
            }
            if parent < 0
                || Darwin.unlinkat(parent, components.last!, 0) != 0 {
                success = false
            }
            if parent >= 0 { Darwin.close(parent) }
        }
        for directory in extraction.directories.reversed() {
            if Darwin.unlinkat(
                extraction.rootDescriptor,
                directory,
                AT_REMOVEDIR
            ) != 0 { success = false }
        }
        if let current = try? Self.snapshotDirectory(extraction.rootDescriptor) {
            if !Self.sameIdentity(current, extraction.rootSnapshot) {
                success = false
            }
        } else {
            success = false
        }
        Darwin.close(extraction.rootDescriptor)
        if success,
           Darwin.unlinkat(
            extraction.parentDescriptor,
            extraction.rootName,
            AT_REMOVEDIR
           ) != 0 { success = false }
        if Darwin.fsync(extraction.parentDescriptor) != 0 { success = false }
        Darwin.close(extraction.parentDescriptor)
        return success
    }

    func removeStagedFiles(
        _ names: [String],
        operationDescriptor: Int32
    ) throws {
        for name in names {
            if Darwin.unlinkat(operationDescriptor, name, 0) != 0,
               errno != ENOENT {
                throw StreamingArchiveFailureV1.cleanupFailed
            }
        }
        guard Darwin.fsync(operationDescriptor) == 0 else {
            throw StreamingArchiveFailureV1.cleanupFailed
        }
    }

    static func openRelativeDirectory(
        _ relative: String,
        rootDescriptor: Int32
    ) throws -> Int32 {
        if relative.isEmpty {
            let duplicate = Darwin.dup(rootDescriptor)
            guard duplicate >= 0 else { throw mapOpenFailure() }
            return duplicate
        }
        let descriptor = Darwin.openat(
            rootDescriptor,
            relative,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw mapOpenFailure() }
        return descriptor
    }

    func canonicalIndexData(_ index: StreamingArchiveIndexV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do { return try encoder.encode(index) }
        catch { throw StreamingArchiveFailureV1.invalidPlan }
    }

    func decodeCanonicalIndex(_ data: Data) throws -> StreamingArchiveIndexV1 {
        do {
            let value = try JSONDecoder().decode(StreamingArchiveIndexV1.self, from: data)
            guard try canonicalIndexData(value) == data else {
                throw StreamingArchiveFailureV1.invalidArchive
            }
            return value
        } catch let failure as StreamingArchiveFailureV1 {
            throw failure
        } catch {
            throw StreamingArchiveFailureV1.invalidArchive
        }
    }

    static func makeHeader(indexByteCount: Int64, indexDigest: Data) -> Data {
        var data = StreamingArchiveFormatV1.magic
        append(StreamingArchiveFormatV1.version, to: &data)
        append(StreamingArchiveFormatV1.flags, to: &data)
        append(UInt64(indexByteCount), to: &data)
        data.append(indexDigest)
        return data
    }

    func parseHeader(_ data: Data) throws -> (indexByteCount: Int64, indexDigest: Data) {
        guard data.count == StreamingArchiveFormatV1.headerByteCount,
              StreamingArchiveFormatV1.hasMagic(data),
              unsigned16(data, at: 8) == StreamingArchiveFormatV1.version,
              unsigned16(data, at: 10) == StreamingArchiveFormatV1.flags else {
            throw StreamingArchiveFailureV1.unsupportedFormat
        }
        let length = unsigned64(data, at: 12)
        guard length > 0, length <= UInt64(Int64.max) else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        return (
            Int64(length),
            data.subdata(in: 20..<StreamingArchiveFormatV1.headerByteCount)
        )
    }

    static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    func unsigned16(_ data: Data, at offset: Int) -> UInt16 {
        data[offset..<(offset + 2)].reduce(UInt16(0)) {
            ($0 << 8) | UInt16($1)
        }
    }

    func unsigned64(_ data: Data, at offset: Int) -> UInt64 {
        data[offset..<(offset + 8)].reduce(UInt64(0)) {
            ($0 << 8) | UInt64($1)
        }
    }

    static func readExactly(descriptor: Int32, byteCount: Int) throws -> Data {
        guard byteCount >= 0 else { throw StreamingArchiveFailureV1.invalidArchive }
        var output = Data()
        output.reserveCapacity(byteCount)
        var buffer = [UInt8](repeating: 0, count: min(64 * 1_024, max(1, byteCount)))
        while output.count < byteCount {
            let requested = min(buffer.count, byteCount - output.count)
            let count = try readSome(
                descriptor: descriptor,
                buffer: &buffer,
                requested: requested
            )
            guard count > 0 else {
                throw StreamingArchiveFailureV1.invalidArchive
            }
            output.append(contentsOf: buffer[0..<count])
        }
        return output
    }

    static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                var count: Int
                repeat {
                    count = Darwin.write(
                        descriptor,
                        base.advanced(by: offset),
                        bytes.count - offset
                    )
                } while count < 0 && errno == EINTR
                guard count > 0 else { throw mapWriteFailure() }
                offset += count
            }
        }
    }

    static func readSome(
        descriptor: Int32,
        buffer: inout [UInt8],
        requested: Int
    ) throws -> Int {
        var count: Int = -1
        repeat {
            count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, requested)
            }
        } while count < 0 && errno == EINTR
        guard count >= 0 else { throw mapReadFailure() }
        return count
    }

    static func snapshotRegularFile(
        _ descriptor: Int32
    ) throws -> StreamingArchiveSourceSnapshotV1 {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0,
              (value.st_mode & S_IFMT) == S_IFREG,
              value.st_nlink == 1,
              value.st_size >= 0 else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        return snapshot(value)
    }

    static func snapshotDirectory(
        _ descriptor: Int32
    ) throws -> StreamingArchiveSourceSnapshotV1 {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0,
              (value.st_mode & S_IFMT) == S_IFDIR else {
            throw StreamingArchiveFailureV1.invalidDestination
        }
        return snapshot(value)
    }

    static func snapshot(_ value: stat) -> StreamingArchiveSourceSnapshotV1 {
        StreamingArchiveSourceSnapshotV1(
            device: UInt64(value.st_dev),
            inode: UInt64(value.st_ino),
            linkCount: UInt64(value.st_nlink),
            byteCount: Int64(value.st_size),
            modifiedSeconds: Int64(value.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec),
            changedSeconds: Int64(value.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(value.st_ctimespec.tv_nsec)
        )
    }

    static func openDirectory(_ url: URL) throws -> Int32 {
        let descriptor = Darwin.open(
            url.standardizedFileURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw mapOpenFailure() }
        return descriptor
    }

    static func existsNoFollow(parent: Int32, name: String) -> Bool {
        var value = stat()
        if Darwin.fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) == 0 {
            return true
        }
        return errno != ENOENT
    }

    static func identityMatches(
        parent: Int32,
        name: String,
        snapshot: StreamingArchiveSourceSnapshotV1
    ) -> Bool {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        guard let current = try? snapshotRegularFile(descriptor) else { return false }
        return current.device == snapshot.device
            && current.inode == snapshot.inode
            && current.linkCount == 1
    }

    static func unlinkCreatedFile(
        parent: Int32,
        name: String,
        snapshot: StreamingArchiveSourceSnapshotV1?
    ) -> Bool {
        if let snapshot,
           !identityMatches(parent: parent, name: name, snapshot: snapshot) {
            return false
        }
        if Darwin.unlinkat(parent, name, 0) != 0, errno != ENOENT {
            return false
        }
        return Darwin.fsync(parent) == 0
    }

    static func sameIdentity(
        _ lhs: StreamingArchiveSourceSnapshotV1,
        _ rhs: StreamingArchiveSourceSnapshotV1
    ) -> Bool {
        lhs.device == rhs.device
            && lhs.inode == rhs.inode
            && lhs.linkCount == rhs.linkCount
    }

    static func matchesRootIdentity(
        _ snapshot: StreamingArchiveSourceSnapshotV1,
        _ expected: StreamingArchiveRootIdentityV1
    ) -> Bool {
        snapshot.device == expected.device && snapshot.inode == expected.inode
    }

    static func validLeaf(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && !value.contains("/") && !value.contains("\\")
            && value == value.precomposedStringWithCanonicalMapping
    }

    func canonicalUUIDLeaf(_ value: String, suffix: String) -> Bool {
        guard value.hasSuffix(suffix) else { return false }
        let raw = String(value.dropLast(suffix.count))
        guard let id = UUID(uuidString: raw) else { return false }
        return canonical(id) == raw
    }

    func validSourceRelativePath(_ value: String) -> Bool {
        guard value == value.precomposedStringWithCanonicalMapping,
              !value.isEmpty,
              value.utf8.count <= limits.maximumPathUTF8ByteCount,
              !value.hasPrefix("/"),
              !value.contains("\\"),
              !value.unicodeScalars.contains(where: {
                $0.value == 0 || $0.value < 0x20 || $0.value == 0x7f
              }) else {
            return false
        }
        let components = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !components.isEmpty && components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
                && String($0) == String($0).precomposedStringWithCanonicalMapping
        }
    }

    func collisionKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(
            options: [
                .caseInsensitive,
                .diacriticInsensitive,
                .widthInsensitive,
            ],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    static func lowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57)
                || ($0.value >= 97 && $0.value <= 102)
        }
    }

    static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static func adding(
        _ lhs: Int64,
        _ rhs: Int64,
        maximum: Int64,
        failure: StreamingArchiveFailureV1
    ) throws -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, sum >= 0, sum <= maximum else { throw failure }
        return sum
    }

    static func map(_ error: Error) -> StreamingArchiveFailureV1 {
        if let failure = error as? StreamingArchiveFailureV1 { return failure }
        if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
            return .protectedDataUnavailable
        }
        if let storage = error as? StoragePreflightError {
            switch storage {
            case .insufficientCapacity: return .insufficientStorage
            case .capacityUnavailable, .capacityEstimateOverflow: return .ioFailure
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC) {
            return .insufficientStorage
        }
        return .ioFailure
    }

    static func mapOpenFailure() -> StreamingArchiveFailureV1 {
        switch errno {
        case EACCES, EPERM: return .protectedDataUnavailable
        case ENOSPC: return .insufficientStorage
        default: return .invalidArchive
        }
    }

    static func mapReadFailure() -> StreamingArchiveFailureV1 {
        switch errno {
        case EACCES, EPERM: return .protectedDataUnavailable
        default: return .ioFailure
        }
    }

    static func mapWriteFailure() -> StreamingArchiveFailureV1 {
        switch errno {
        case ENOSPC, EDQUOT: return .insufficientStorage
        case EACCES, EPERM: return .protectedDataUnavailable
        default: return .ioFailure
        }
    }
}

enum C45AcceptedLabelStreamingArchiveServiceBoundaryV1 { static let validatesSnapshotDigestBeforeWrite=true;static let neverStagesRendererOutputAsBackupTruth=true }

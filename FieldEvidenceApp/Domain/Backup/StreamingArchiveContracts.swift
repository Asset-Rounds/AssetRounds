import Foundation

enum GuidedSurveyStreamingArchivePolicyV1 {
    static let recordsSchemaVersion = 24
    static let durableFamilyCount = 5
    static let lifecycleEventsRemainInMutationHistory = true
}

/// C27 keeps locator rows in the same bounded archive stream as the other
/// backup records.  The stream carries public locator material and immutable
/// binding receipts only; resolution previews and private signing material are
/// never archive members.
enum AssetLocatorStreamingArchivePolicyV1 {
    static let recordsSchemaVersion = 25
    static let persistentSchemaVersion = 26
    static let durableFamilyCount = 2
    static let lifecycleEventsRemainInMutationHistory = true
    static let sameWorkspacePreservesPublicSignedPayload = true
    static let cloneForkSourceSignatureActive = false
    static let privateKeyMaterialMayBeExported = false

    static func validate(records: V4BackupRecordsV1) throws {
        // Schema 26 carries the prior locator family alongside schedules;
        // locator validation remains valid when it is embedded in that
        // successor package.
        guard (1...26).contains(records.recordsSchemaVersion) else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        guard records.recordsSchemaVersion < recordsSchemaVersion else {
            guard records.assetLocators.count <= 200_000 else {
                throw StreamingArchiveFailureV1.entryLimitExceeded
            }
            var locators: [AssetLocatorV1] = []
            var receipts: [LocatorBindingReceiptV1] = []
            for record in records.assetLocators {
                do {
                    switch record.kind {
                    case .locator:
                        let value = try AssetLocatorCanonicalCodecV1.decode(
                            AssetLocatorV1.self, from: record.canonicalData
                        )
                        guard value.locatorID == record.id,
                              value.workspaceID.rawValue == record.workspaceID,
                              value.revision == record.revision else {
                            throw StreamingArchiveFailureV1.invalidArchive
                        }
                        locators.append(value)
                    case .bindingReceipt:
                        let value = try AssetLocatorCanonicalCodecV1.decode(
                            LocatorBindingReceiptV1.self, from: record.canonicalData
                        )
                        guard value.receiptID == record.id,
                              value.workspaceID.rawValue == record.workspaceID,
                              value.revision == record.revision else {
                            throw StreamingArchiveFailureV1.invalidArchive
                        }
                        receipts.append(value)
                    }
                } catch let error as StreamingArchiveFailureV1 {
                    throw error
                } catch {
                    throw StreamingArchiveFailureV1.invalidArchive
                }
            }
            do {
                try AssetLocatorLifecycleClosureV1(
                    locators: locators, receipts: receipts
                ).validate()
            } catch {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
    }
}

/// C28 archive policy: immutable schedule releases and append-only occurrence
/// history are portable; due/reminder projections and generation plans are
/// reconstructed after restore and never become archive truth.
enum ScheduleStreamingArchivePolicyV1 {
    static let recordsSchemaVersion = 26
    static let persistentSchemaVersion = 27
    static let durableFamilyCount = 2
    static let lifecycleEventsRemainInMutationHistory = true
    static let derivedProjectionsAreExcluded = true
    static let notificationStateIsTruth = false
    static let cloneForkSourceScheduleAutomaticallyActive = false

    static func validate(records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion <= recordsSchemaVersion else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        guard records.schedules.count <= 200_000,
              derivedProjectionsAreExcluded,
              !notificationStateIsTruth,
              !cloneForkSourceScheduleAutomaticallyActive else {
            throw StreamingArchiveFailureV1.entryLimitExceeded
        }
        do {
            let bytes = try BackupCanonicalEncoderV1().encodeRecords(records).data
            _ = try BackupCanonicalDecoderV1().decodeRecords(bytes)
        } catch {
            throw StreamingArchiveFailureV1.invalidArchive
        }
    }
}

/// C29 archive boundary: plan documents, immutable revision history, their
/// spatial frames, placements, and rebase receipts travel together.  A
/// rebase preview and component registry are derived inputs and are rebuilt
/// after extraction; neither is an archive truth source.
enum PlanStreamingArchivePolicyV1 {
    static let recordsSchemaVersion = 27
    static let persistentSchemaVersion = 28
    static let durableFamilyCount = 4
    static let archiveFamilyCount = 5
    static let derivedProjectionStorage = "NONPERSISTENT_REBUILD"
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let cloneForkSourcePlanAutomaticallyActive = false
    static let componentRegistryIsArchiveTruth = false

    static func validate(records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion <= recordsSchemaVersion else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        guard records.recordsSchemaVersion < recordsSchemaVersion ||
                records.plans.count <= PlanLimitsV1.maximumPlacements * 5,
              derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              !cloneForkSourcePlanAutomaticallyActive,
              !componentRegistryIsArchiveTruth else {
            throw StreamingArchiveFailureV1.entryLimitExceeded
        }
        guard records.recordsSchemaVersion < recordsSchemaVersion ||
                records.mutationHistory != nil else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        do {
            guard archiveFamilyCount == V28BackupPlanRecordV1.Kind.allCases.count else {
                throw StreamingArchiveFailureV1.invalidArchive
            }
            try V28PlanImportBoundaryV1.validate(
                persistent: persistentSchemaVersion,
                records: recordsSchemaVersion
            )
            _ = try PlanBackupRecordSetV1.decode(records.plans)
        } catch {
            throw StreamingArchiveFailureV1.invalidArchive
        }
    }
}

enum StreamingArchiveCompressionV1: String, Codable, CaseIterable, Sendable {
    case stored
    case zlib
}

struct StreamingArchiveLimitsV1: Codable, Equatable, Sendable {
    static let card17 = StreamingArchiveLimitsV1(
        maximumIndexByteCount: 4 * 1_048_576,
        maximumEntryCount: 10_000,
        maximumPathUTF8ByteCount: 512,
        maximumStoredEntryByteCount: 512 * 1_048_576,
        maximumUncompressedEntryByteCount: 512 * 1_048_576,
        maximumStoredAggregateByteCount: 4 * 1_073_741_824,
        maximumUncompressedAggregateByteCount: 4 * 1_073_741_824,
        maximumCompressionRatio: 100,
        bufferByteCount: 64 * 1_024,
        stagingReserveByteCount: 64 * 1_048_576
    )
    static let card25SurveyTemplate = StreamingArchiveLimitsV1(
        maximumIndexByteCount: 1_048_576,
        maximumEntryCount: 128,
        maximumPathUTF8ByteCount: 240,
        maximumStoredEntryByteCount: 8 * 1_048_576,
        maximumUncompressedEntryByteCount: 8 * 1_048_576,
        maximumStoredAggregateByteCount: 16 * 1_048_576,
        maximumUncompressedAggregateByteCount: 16 * 1_048_576,
        maximumCompressionRatio: 20,
        bufferByteCount: 64 * 1_024,
        stagingReserveByteCount: 16 * 1_048_576
    )

    let maximumIndexByteCount: Int
    let maximumEntryCount: Int
    let maximumPathUTF8ByteCount: Int
    let maximumStoredEntryByteCount: Int64
    let maximumUncompressedEntryByteCount: Int64
    let maximumStoredAggregateByteCount: Int64
    let maximumUncompressedAggregateByteCount: Int64
    let maximumCompressionRatio: Int64
    let bufferByteCount: Int
    let stagingReserveByteCount: Int64

    func validate() throws {
        guard maximumIndexByteCount > 0,
              maximumEntryCount > 0,
              maximumPathUTF8ByteCount > 0,
              maximumStoredEntryByteCount > 0,
              maximumUncompressedEntryByteCount > 0,
              maximumStoredAggregateByteCount > 0,
              maximumUncompressedAggregateByteCount > 0,
              maximumCompressionRatio > 0,
              bufferByteCount >= 4_096,
              bufferByteCount <= 1_048_576,
              stagingReserveByteCount >= 0 else {
            throw StreamingArchiveFailureV1.invalidLimits
        }
    }
}

enum StreamingArchivePathProfileV1:String,Codable,Sendable{case backupV4="BACKUP_V4",surveyTemplate="SURVEY_TEMPLATE"}
enum SurveyTemplateArchiveAdmissionV1{
    static let maximumTotalBytes:Int64=16*1_048_576,maximumEntryBytes:Int64=8*1_048_576,maximumEntries=128,maximumPathUTF8Bytes=240,maximumDepth=8,maximumCompressionRatio:Int64=20
    static func validate(_ index:StreamingArchiveIndexV1)throws{guard !index.entries.isEmpty,index.entries.count<=maximumEntries,index.storedPayloadByteCount<=maximumTotalBytes,index.uncompressedPayloadByteCount<=maximumTotalBytes else{throw StreamingArchiveFailureV1.entryLimitExceeded};for entry in index.entries{let depth=entry.path.split(separator:"/",omittingEmptySubsequences:false).count;guard entry.path.utf8.count<=maximumPathUTF8Bytes,(1...maximumDepth).contains(depth),entry.storedByteCount>=0,entry.uncompressedByteCount>=0,entry.storedByteCount<=maximumEntryBytes,entry.uncompressedByteCount<=maximumEntryBytes else{throw StreamingArchiveFailureV1.hostilePath};if entry.storedByteCount==0{guard entry.uncompressedByteCount==0 else{throw StreamingArchiveFailureV1.compressionRatioExceeded}}else{guard entry.uncompressedByteCount<=entry.storedByteCount*maximumCompressionRatio else{throw StreamingArchiveFailureV1.compressionRatioExceeded}}}}
}

struct StreamingArchiveEntryV1: Codable, Equatable, Sendable {
    let path: String
    let mimeType: String
    let compression: StreamingArchiveCompressionV1
    let storedByteCount: Int64
    let uncompressedByteCount: Int64
    let storedSHA256: String
    let contentSHA256: String
}

struct StreamingArchiveIndexV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let archiveSchemaVersion: Int
    let entries: [StreamingArchiveEntryV1]
    let storedPayloadByteCount: Int64
    let uncompressedPayloadByteCount: Int64
}

struct StreamingArchiveWriteEntryV1: Equatable, Sendable {
    let path: String
    let mimeType: String
    let sourceRootURL: URL
    let sourceRelativePath: String
    let expectedSourceRootIdentity: StreamingArchiveRootIdentityV1
    let expectedUncompressedByteCount: Int64
    let expectedContentSHA256: String
    let compression: StreamingArchiveCompressionV1

    init(
        path: String,
        mimeType: String,
        sourceRootURL: URL,
        sourceRelativePath: String,
        expectedSourceRootIdentity: StreamingArchiveRootIdentityV1,
        expectedUncompressedByteCount: Int64,
        expectedContentSHA256: String,
        compression: StreamingArchiveCompressionV1
    ) {
        self.path = path
        self.mimeType = mimeType
        self.sourceRootURL = sourceRootURL
        self.sourceRelativePath = sourceRelativePath
        self.expectedSourceRootIdentity = expectedSourceRootIdentity
        self.expectedUncompressedByteCount = expectedUncompressedByteCount
        self.expectedContentSHA256 = expectedContentSHA256
        self.compression = compression
    }
}

struct StreamingArchiveRootIdentityV1: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64

    init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

struct StreamingArchiveWritePlanV1: Equatable, Sendable {
    let entries: [StreamingArchiveWriteEntryV1]
    let stagingDirectoryURL: URL

    init(entries: [StreamingArchiveWriteEntryV1], stagingDirectoryURL: URL) {
        self.entries = entries
        self.stagingDirectoryURL = stagingDirectoryURL
    }
}

struct StreamingArchiveSourceSnapshotV1: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let linkCount: UInt64
    let byteCount: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}

struct StreamingArchiveWriteReceiptV1: Equatable, Sendable {
    let archiveURL: URL
    let archiveByteCount: Int64
    let archiveSHA256: String
    let index: StreamingArchiveIndexV1
}

struct StreamingArchiveExtractionV1: Equatable, Sendable {
    let archiveURL: URL
    let extractedDirectoryURL: URL
    let archiveSHA256: String
    let index: StreamingArchiveIndexV1
}

struct StreamingArchiveCancellationV1: @unchecked Sendable {
    let checkpoint: () throws -> Void

    init(checkpoint: @escaping () throws -> Void) {
        self.checkpoint = checkpoint
    }

    static let none = StreamingArchiveCancellationV1(checkpoint: {})

    static let task = StreamingArchiveCancellationV1 {
        if Task.isCancelled {
            throw StreamingArchiveFailureV1.cancelled
        }
    }
}

enum StreamingArchiveFailureV1: Error, Equatable, Sendable {
    case invalidLimits
    case invalidPlan
    case invalidDestination
    case destinationExists
    case invalidArchive
    case unsupportedFormat
    case hostilePath
    case duplicatePath
    case entryLimitExceeded
    case storedLimitExceeded
    case uncompressedLimitExceeded
    case compressionRatioExceeded
    case sourceChanged
    case contentMismatch
    case insufficientStorage
    case protectedDataUnavailable
    case cancelled
    case cleanupFailed
    case ioFailure
}

enum StreamingArchiveFormatV1 {
    static let magic = Data([0x41, 0x53, 0x52, 0x42, 0x41, 0x31, 0x0d, 0x0a])
    static let version: UInt16 = 1
    static let flags: UInt16 = 0
    static let digestByteCount = 32
    static let headerByteCount = 8 + 2 + 2 + 8 + digestByteCount

    static func hasMagic(_ prefix: Data) -> Bool {
        prefix.count >= magic.count && prefix.prefix(magic.count) == magic
    }
}

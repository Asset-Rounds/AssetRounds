import Foundation

enum C50IncumbentFileExchangeStreamingArchiveBoundaryV1 {
    static let adapterSourceMemberCount = 0
    static let adapterQuarantineMemberCount = 0
    static let profileSelectionMemberCount = 0
    static let backupArchiveParserIsAdapterParser = false
    static let canonicalImportedRowsRemainStreamedByExistingFamilies = true

    static func validate(recordsSchemaVersion: Int) -> Bool {
        recordsSchemaVersion <= C50IncumbentFileExchangeBackupBoundaryV1.recordsSchemaVersion
            && adapterSourceMemberCount == 0
            && adapterQuarantineMemberCount == 0
            && profileSelectionMemberCount == 0
            && !backupArchiveParserIsAdapterParser
            && canonicalImportedRowsRemainStreamedByExistingFamilies
    }
}

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
    static let durableFamilyCount = 4
    static let lifecycleEventsRemainInMutationHistory = true
    static let derivedProjectionsAreExcluded = true
    static let notificationStateIsTruth = false
    static let cloneForkSourceScheduleAutomaticallyActive = false
    static let interruptionResumesAtCanonicalRecordBoundary = true
    static let partialClosureMayPublish = false
    static let calendarOverrideBasisClosureUsesExistingRecordKinds = true

    static func validate(records: V4BackupRecordsV1) throws {
        guard (recordsSchemaVersion...C49BackupEnrollmentV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion) else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        guard records.schedules.count <= 200_000,
              C51ScheduleBackupClosureV1.validatesEnvelope(records.schedules) || records.schedules.isEmpty,
              derivedProjectionsAreExcluded,
              interruptionResumesAtCanonicalRecordBoundary,
              !partialClosureMayPublish,
              calendarOverrideBasisClosureUsesExistingRecordKinds,
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
        guard (recordsSchemaVersion...C49BackupEnrollmentV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion) else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        guard records.plans.count <= PlanLimitsV1.maximumPlacements * 5,
              derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              !cloneForkSourcePlanAutomaticallyActive,
              !componentRegistryIsArchiveTruth else {
            throw StreamingArchiveFailureV1.entryLimitExceeded
        }
        guard records.mutationHistory != nil else {
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

/// C37 transports the immutable pose-event and spatial-anchor histories as a
/// single closure. Current tips, completed snapshots, and editor state are
/// rebuilt after extraction; raw sensor/proposal values are never archive
/// members. Clone/fork restore must explicitly rebind the history before it
/// can participate in a destination workspace projection.
enum PlacementPoseStreamingArchivePolicyV1 {
    static let recordsSchemaVersion = 28
    static let persistentSchemaVersion = 29
    static let durableFamilyCount = 2
    static let archiveFamilyCount = 2
    static let derivedProjectionStorage = "NONPERSISTENT_REBUILD"
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let sensorProposalPersistence = "NONPERSISTENT"
    static let cloneForkSourcePoseAutomaticallyActive = false

    static func validate(records: V4BackupRecordsV1) throws {
        guard (recordsSchemaVersion...C49BackupEnrollmentV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion),
              derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              sensorProposalPersistence == "NONPERSISTENT",
              !cloneForkSourcePoseAutomaticallyActive else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        guard records.placementPoses.count <= PlacementPoseLimitsV1.maximumEventsPerClosure * 2,
              archiveFamilyCount == V29BackupPlacementPoseRecordV1.Kind.allCases.count,
              records.mutationHistory != nil else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        do {
            try V29PlacementPoseImportBoundaryV1.validate(
                persistent: persistentSchemaVersion,
                records: recordsSchemaVersion
            )
            _ = try PlacementPoseBackupRecordSetV1.decode(records.placementPoses)
        } catch {
            throw StreamingArchiveFailureV1.invalidArchive
        }
    }
}

enum C30EvidenceContextStreamingArchivePolicyV1 {
    static let archiveKinds = V30BackupEvidenceContextRecordV1.Kind.allCases
    static let canonicalRowsOnly = true
    static let derivedProjectionDisposition = "DROP_AND_REBUILD"
    static let externalProviderStateIncluded = false

    static func validate(records: [V30BackupEvidenceContextRecordV1]) throws {
        guard archiveKinds.count == 2, canonicalRowsOnly,
              derivedProjectionDisposition == "DROP_AND_REBUILD",
              !externalProviderStateIncluded else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        _ = try EvidenceContextBackupRecordSetV1.decode(records)
    }
}

enum C31LightingStreamingArchivePolicyV1 {
    static let archiveKinds = V31BackupLightingRecordV1.Kind.allCases
    static let canonicalRowsOnly = true
    static let derivedProjectionDisposition = "DROP_AND_REBUILD"
    static let externalProviderStateIncluded = false
    static let licensedCriterionTextIncluded = false
    static let durableFamilyCount = 5

    static func validate(records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion == 30 || records.recordsSchemaVersion == 31
                || records.recordsSchemaVersion == 32
                || records.recordsSchemaVersion == 33 || records.recordsSchemaVersion == 34
                || records.recordsSchemaVersion == C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion
                || records.recordsSchemaVersion == C49BackupEnrollmentV1.recordsSchemaVersion,
              archiveKinds.count == durableFamilyCount,
              canonicalRowsOnly,
              derivedProjectionDisposition == "DROP_AND_REBUILD",
              !externalProviderStateIncluded,
              !licensedCriterionTextIncluded else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        do {
            _ = try LightingBackupRecordSetV1.decode(records.lighting)
        } catch {
            throw StreamingArchiveFailureV1.invalidArchive
        }
    }
}

/// C32 carries accepted receipts as immutable canonical mutation provenance.
/// Review proposals, rejected/cancelled corpora, and leased scratch are never
/// archive entries.
enum C32AssistanceStreamingArchivePolicyV1 {
    static let recordsSchemaVersion = 31
    static let durableFamilyCount = 1
    static let proposalArchiveDisposition = "EXCLUDED_NONPERSISTENT"

    static func validate(records: V4BackupRecordsV1) throws {
        guard (recordsSchemaVersion...C49BackupEnrollmentV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion),
              durableFamilyCount == AssistancePersistenceEnrollmentV1.durableModelCount,
              proposalArchiveDisposition == "EXCLUDED_NONPERSISTENT" else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        do { try records.validateC32AssistanceAcceptanceReceipts() }
        catch { throw StreamingArchiveFailureV1.invalidArchive }
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
    static let card48PortableReviewRequest = StreamingArchiveLimitsV1(
        maximumIndexByteCount: 256 * 1_024,
        maximumEntryCount: 37,
        maximumPathUTF8ByteCount: 240,
        maximumStoredEntryByteCount: 32 * 1_048_576,
        maximumUncompressedEntryByteCount: 32 * 1_048_576,
        maximumStoredAggregateByteCount: 64 * 1_048_576,
        maximumUncompressedAggregateByteCount: 64 * 1_048_576,
        maximumCompressionRatio: 1,
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

enum StreamingArchivePathProfileV1:String,Codable,Sendable{
    case backupV4="BACKUP_V4"
    case surveyTemplate="SURVEY_TEMPLATE"
    case portableReviewRequest="PORTABLE_REVIEW_REQUEST"
}
enum SurveyTemplateArchiveAdmissionV1{
    static let maximumTotalBytes:Int64=16*1_048_576,maximumEntryBytes:Int64=8*1_048_576,maximumEntries=128,maximumPathUTF8Bytes=240,maximumDepth=8,maximumCompressionRatio:Int64=20
    static func validate(_ index:StreamingArchiveIndexV1)throws{guard !index.entries.isEmpty,index.entries.count<=maximumEntries,index.storedPayloadByteCount<=maximumTotalBytes,index.uncompressedPayloadByteCount<=maximumTotalBytes else{throw StreamingArchiveFailureV1.entryLimitExceeded};for entry in index.entries{let depth=entry.path.split(separator:"/",omittingEmptySubsequences:false).count;guard entry.path.utf8.count<=maximumPathUTF8Bytes,(1...maximumDepth).contains(depth),entry.storedByteCount>=0,entry.uncompressedByteCount>=0,entry.storedByteCount<=maximumEntryBytes,entry.uncompressedByteCount<=maximumEntryBytes else{throw StreamingArchiveFailureV1.hostilePath};if entry.storedByteCount==0{guard entry.uncompressedByteCount==0 else{throw StreamingArchiveFailureV1.compressionRatioExceeded}}else{guard entry.uncompressedByteCount<=entry.storedByteCount*maximumCompressionRatio else{throw StreamingArchiveFailureV1.compressionRatioExceeded}}}}
}

/// The review request is a bounded cleartext use of the released streaming
/// archive framing. It is deliberately a profile, not a second archive
/// parser. The response remains one canonical JSON document and never enters
/// this archive grammar.
enum PortableReviewRequestArchiveAdmissionV1 {
    static let fileExtension = "arreviewrequest"
    static let responseFileExtension = "arreviewresponse"
    static let requestTypeIdentifier = "com.assetrounds.review-request"
    static let responseTypeIdentifier = "com.assetrounds.review-response"
    static let maximumMediaEntries = 32
    static let maximumEntries = 5 + maximumMediaEntries
    static let maximumDepth = 2
    static let responseCapabilityByteCount = Int64(PortableReviewLimitsV1.capabilityByteCount)
    static let maximumAggregateBytes: Int64 = 64 * 1_048_576
    static let requiredEntries: [String: String] = [
        ReviewRequestFileEntryV1.manifest.rawValue: "application/json",
        ReviewRequestFileEntryV1.request.rawValue: "application/json",
        ReviewRequestFileEntryV1.responseCapability.rawValue: "application/octet-stream",
        ReviewRequestFileEntryV1.reportPDF.rawValue: "application/pdf",
        ReviewRequestFileEntryV1.reportText.rawValue: "text/plain",
    ]

    static func validate(_ index: StreamingArchiveIndexV1) throws {
        try validateDeclaredEntries(index.entries.map {
            ($0.path, $0.mimeType, $0.uncompressedByteCount)
        })
        guard index.storedPayloadByteCount == index.uncompressedPayloadByteCount,
              index.uncompressedPayloadByteCount <= maximumAggregateBytes else {
            throw StreamingArchiveFailureV1.uncompressedLimitExceeded
        }
    }

    static func validateDeclaredEntries(
        _ entries: [(path: String, mimeType: String, byteCount: Int64)]
    ) throws {
        guard entries.count >= requiredEntries.count,
              entries.count <= maximumEntries else {
            throw StreamingArchiveFailureV1.entryLimitExceeded
        }
        var values: [String: (path: String, mimeType: String, byteCount: Int64)] = [:]
        for entry in entries {
            guard values.updateValue(entry, forKey: entry.path) == nil else {
                throw StreamingArchiveFailureV1.duplicatePath
            }
        }
        for (path, mimeType) in requiredEntries {
            guard let entry = values[path], entry.mimeType == mimeType else {
                throw StreamingArchiveFailureV1.invalidArchive
            }
        }
        guard values[ReviewRequestFileEntryV1.responseCapability.rawValue]?.byteCount
                == responseCapabilityByteCount else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        let media = entries.filter { $0.path.hasPrefix("media/") }
        guard media.count <= maximumMediaEntries,
              entries.allSatisfy({ requiredEntries[$0.path] != nil || $0.path.hasPrefix("media/") }),
              entries.allSatisfy({ $0.byteCount >= 0 }),
              entries.reduce(Int64(0), { partial, entry in
                  let (sum, overflow) = partial.addingReportingOverflow(entry.byteCount)
                  return overflow ? Int64.max : sum
              }) <= maximumAggregateBytes else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
    }
}

/// A response is a single bounded canonical JSON value, never an archive.
/// Decoding delegates to the released C48 codec so this boundary cannot
/// acquire a competing response grammar.
enum PortableReviewResponseFileAdmissionV1 {
    static let maximumByteCount = PortableReviewLimitsV1.maximumResponseBytes

    static func validate(_ bytes: Data) throws -> CanonicalReviewResponseBytesV1 {
        guard !bytes.isEmpty, bytes.count <= maximumByteCount else {
            throw PortableReviewFailureV1.invalidValue
        }
        return try CanonicalReviewResponseBytesV1(canonicalBytes: bytes)
    }
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

enum C45AcceptedLabelStreamingArchiveBoundaryV1 { static let canonicalSnapshotIsStreamed=true;static let projectionOutputMembersAreExcluded=true }
enum C47ActivityContractStreamingArchiveBoundaryV2 {
    static let recordsSchemaVersion = 35
    static let fiveCanonicalRowFamiliesAreStreamed = true
    static let completedSnapshotRemainsReleasedReportMember = true
    static let nonpersistentReceiptsAreExcluded = true

    static func validate(records: V4BackupRecordsV1) throws {
        guard (recordsSchemaVersion...C49BackupEnrollmentV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion),
              fiveCanonicalRowFamiliesAreStreamed,
              completedSnapshotRemainsReleasedReportMember,
              nonpersistentReceiptsAreExcluded else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        do { _ = try records.validateC47ActivityContracts() }
        catch { throw StreamingArchiveFailureV1.invalidArchive }
    }
}

enum C49WorkResourceStreamingArchiveBoundaryV1 {
    static let recordsSchemaVersion = C49BackupEnrollmentV1.recordsSchemaVersion
    static let canonicalRowsShareRecordsEnvelope = true
    static let totalsSearchDraftsAndLiveStockAreExcluded = true

    static func validate(records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion == recordsSchemaVersion,
              canonicalRowsShareRecordsEnvelope,
              totalsSearchDraftsAndLiveStockAreExcluded else {
            throw StreamingArchiveFailureV1.invalidArchive
        }
        do { _ = try records.validateC49WorkResources() }
        catch { throw StreamingArchiveFailureV1.invalidArchive }
    }
}

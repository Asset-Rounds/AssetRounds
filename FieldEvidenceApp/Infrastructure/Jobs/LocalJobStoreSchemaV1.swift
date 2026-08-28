import Foundation

enum LocalJobStoreFailureV1: Error, Equatable, Sendable {
    case invalidRoot
    case unsupportedSchemaVersion
    case corruptStore
    case storeLimitExceeded
    case jobAlreadyExists
    case jobNotFound
    case staleJob
    case invalidTransition
    case protectedDataUnavailable
    case storageUnavailable
    case writeFailed
    case cleanupFailed
}

/// Deterministic test seam for protected-file availability. Production uses
/// the default inert closure; the hook cannot inject any other failure class.
enum LocalJobStoreProtectedDataAccessV1: Equatable, Sendable {
    case read
    case write
    case cleanup
}

typealias LocalJobStoreProtectedDataFailureHookV1 = @Sendable (
    LocalJobStoreProtectedDataAccessV1
) -> Bool

enum LocalJobStoreMigrationSourceV1: String, Codable, Equatable, Sendable {
    case absent = "ABSENT"
    case version1 = "VERSION_1"
    case olderVersion = "OLDER_VERSION"
    case unknownOrCorrupt = "UNKNOWN_OR_CORRUPT"
}

enum LocalJobStoreMigrationDispositionV1: String, Codable, Equatable, Sendable {
    case createdEmpty = "CREATED_EMPTY"
    case openedCurrent = "OPENED_CURRENT"
    case migrated = "MIGRATED"
    case quarantinedAndRebuilt = "QUARANTINED_AND_REBUILT"
}

struct LocalJobStoreMigrationReceiptV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let source: LocalJobStoreMigrationSourceV1
    let disposition: LocalJobStoreMigrationDispositionV1
    let sourceStoreVersion: Int?
    let destinationStoreVersion: Int
    let migratedJobCount: Int
    let occurredAt: Date

    init(
        source: LocalJobStoreMigrationSourceV1,
        disposition: LocalJobStoreMigrationDispositionV1,
        sourceStoreVersion: Int?,
        migratedJobCount: Int,
        occurredAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.disposition = disposition
        self.sourceStoreVersion = sourceStoreVersion
        destinationStoreVersion = LocalJobStoreSchemaV1.currentVersion
        self.migratedJobCount = migratedJobCount
        self.occurredAt = occurredAt
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              destinationStoreVersion == LocalJobStoreSchemaV1.currentVersion,
              migratedJobCount >= 0,
              occurredAt.timeIntervalSinceReferenceDate.isFinite else {
            throw LocalJobStoreFailureV1.corruptStore
        }
    }
}

enum LocalJobStoreSchemaV1 {
    static let currentVersion = 1
    static let directoryName = "local-jobs-v1"
    static let storeFileName = "jobs.json"
    static let migrationReceiptFileName = "migration-receipt.json"
    static let quarantineDirectoryName = "quarantine"
    static let maximumJobCount = 10_000
    static let maximumStoreBytes = 32 * 1024 * 1024

    // Frozen operational lifecycle. Checkpoints never become user-authored
    // backup/export content and never acquire the canonical schema lease.
    static let migrationFromAbsentOrOlderVersion = true
    static let includedInUserBackup = false
    static let includedInUserExport = false
    static let restoreImportsCheckpoints = false
    static let restoreRebuildsFromCanonicalIncompleteIntents = true
    static let workspaceDeleteRemovesCheckpoints = true
    static let eraseRemovesCheckpoints = true
    static let expiryRemovesCheckpoints = true
    static let relaunchReplayEnabled = true
    static let downgradeDisposition = "DROP_AND_REBUILD_AFTER_CANONICAL_SURVIVAL_PROOF"

    // C36 attachment jobs remain operational checkpoint rows.  They are
    // rebuilt from canonical staging items after restore and never become
    // backup/export content themselves.
    static let c36AttachmentJobKind = ResumableLocalJobKindV1.draftAttachmentProcessing
    static let c36IncludedInUserBackup = false
    static let c36IncludedInUserExport = false
    static let c36RebuiltFromStagingItems = true
    static let c36MaximumConcurrency = JobScaleBudgetPolicyV1.maximumRunnerConcurrency
}

struct LocalJobStoreEnvelopeV1: Codable, Equatable, Sendable {
    let storeVersion: Int
    let jobs: [ResumableLocalJobV1]

    init(jobs: [ResumableLocalJobV1]) throws {
        storeVersion = LocalJobStoreSchemaV1.currentVersion
        self.jobs = jobs.sorted { Self.key($0.id) < Self.key($1.id) }
        try validate()
    }

    func validate() throws {
        guard storeVersion == LocalJobStoreSchemaV1.currentVersion,
              jobs.count <= LocalJobStoreSchemaV1.maximumJobCount,
              Set(jobs.map(\.id)).count == jobs.count,
              jobs == jobs.sorted(by: { Self.key($0.id) < Self.key($1.id) }) else {
            throw LocalJobStoreFailureV1.corruptStore
        }
        do { try jobs.forEach { try $0.validate() } }
        catch { throw LocalJobStoreFailureV1.corruptStore }
    }

    private static func key(_ id: LocalJobIDV1) -> String {
        id.rawValue.uuidString.lowercased()
    }
}

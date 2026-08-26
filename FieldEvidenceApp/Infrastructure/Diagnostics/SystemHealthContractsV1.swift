import Foundation

enum OperationalDiagnosticsValidationFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case unsupportedVersion
    case registryMismatch
    case limitExceeded
    case privacyViolation
}

enum OperationalFailureDomainV1: String, CaseIterable, Codable, Hashable, Sendable {
    case backup = "BACKUP"
    case capability = "CAPABILITY"
    case cancellation = "CANCELLATION"
    case concurrency = "CONCURRENCY"
    case content = "CONTENT"
    case commerce = "COMMERCE"
    case diagnostics = "DIAGNOSTICS"
    case export = "EXPORT"
    case permission = "PERMISSION"
    case persistence = "PERSISTENCE"
    case protectedData = "PROTECTED_DATA"
    case report = "REPORT"
    case storage = "STORAGE"
}

enum OperationalFailureCodeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case backupExportFailed = "BACKUP_EXPORT_FAILED"
    case backupRestoreFailed = "BACKUP_RESTORE_FAILED"
    case backupSourceChanged = "BACKUP_SOURCE_CHANGED"
    case capabilityUnavailable = "CAPABILITY_UNAVAILABLE"
    case concurrentOperation = "CONCURRENT_OPERATION"
    case contentReadFailed = "CONTENT_READ_FAILED"
    case commerceUnavailable = "COMMERCE_UNAVAILABLE"
    case corruptOperationalStore = "CORRUPT_OPERATIONAL_STORE"
    case diagnosticsWriteFailed = "DIAGNOSTICS_WRITE_FAILED"
    case exportCancelled = "EXPORT_CANCELLED"
    case exportFailed = "EXPORT_FAILED"
    case interrupted = "INTERRUPTED"
    case partialSafeState = "PARTIAL_SAFE_STATE"
    case permissionDenied = "PERMISSION_DENIED"
    case persistenceMigrationRequired = "PERSISTENCE_MIGRATION_REQUIRED"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case reportRenderFailed = "REPORT_RENDER_FAILED"
    case reportUnavailable = "REPORT_UNAVAILABLE"
    case requiredFileMissing = "REQUIRED_FILE_MISSING"
    case restartRequired = "RESTART_REQUIRED"
    case resumeRequired = "RESUME_REQUIRED"
    case storageCapacityInsufficient = "STORAGE_CAPACITY_INSUFFICIENT"
    case storageWriteFailed = "STORAGE_WRITE_FAILED"
    case unknown = "UNKNOWN"
    case userCancelled = "USER_CANCELLED"
}

enum OperationalFailureSeverityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
}

enum OperationalRetryabilityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case notRetryable = "NOT_RETRYABLE"
    case retryAfterConditionChanges = "RETRY_AFTER_CONDITION_CHANGES"
    case retryImmediately = "RETRY_IMMEDIATELY"
}

enum OperationalOperationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case backupExport = "BACKUP_EXPORT"
    case backupRestore = "BACKUP_RESTORE"
    case bootstrap = "BOOTSTRAP"
    case commerce = "COMMERCE"
    case contentRead = "CONTENT_READ"
    case diagnosticsRead = "DIAGNOSTICS_READ"
    case diagnosticsWrite = "DIAGNOSTICS_WRITE"
    case erase = "ERASE"
    case fileAccess = "FILE_ACCESS"
    case metricCollection = "METRIC_COLLECTION"
    case migration = "MIGRATION"
    case reportAvailability = "REPORT_AVAILABILITY"
    case reportRender = "REPORT_RENDER"
    case reset = "RESET"
    case resume = "RESUME"
    case scratchCleanup = "SCRATCH_CLEANUP"
    case supportExport = "SUPPORT_EXPORT"
}

enum OperationalOwnerV1: String, CaseIterable, Codable, Hashable, Sendable {
    case backup = "BACKUP"
    case commerce = "COMMERCE"
    case deviceLifecycle = "DEVICE_LIFECYCLE"
    case diagnosticsStore = "DIAGNOSTICS_STORE"
    case metricReporting = "METRIC_REPORTING"
    case persistence = "PERSISTENCE"
    case reporting = "REPORTING"
    case scratchStore = "SCRATCH_STORE"
    case supportExport = "SUPPORT_EXPORT"
}

enum OperationalActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case cancel = "CANCEL"
    case chooseFile = "CHOOSE_FILE"
    case closeOtherOperation = "CLOSE_OTHER_OPERATION"
    case contactSupport = "CONTACT_SUPPORT"
    case freeStorage = "FREE_STORAGE"
    case none = "NONE"
    case openSettings = "OPEN_SETTINGS"
    case retry = "RETRY"
    case restart = "RESTART"
    case resume = "RESUME"
    case unlockDevice = "UNLOCK_DEVICE"
}

enum OperationalHelpTopicV1: String, CaseIterable, Codable, Hashable, Sendable {
    case backup = "BACKUP"
    case commerce = "COMMERCE"
    case diagnosticsReset = "DIAGNOSTICS_RESET"
    case permissions = "PERMISSIONS"
    case reports = "REPORTS"
    case storage = "STORAGE"
    case supportExport = "SUPPORT_EXPORT"
}

enum OperationalPrivacyClassV1: String, CaseIterable, Codable, Hashable, Sendable {
    case aggregate = "AGGREGATE"
    case publicSystem = "PUBLIC_SYSTEM"
}

enum OperationalFailureFactKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case attemptedBytes = "ATTEMPTED_BYTES"
    case availableBytes = "AVAILABLE_BYTES"
    case itemCount = "ITEM_COUNT"
    case retryAttempt = "RETRY_ATTEMPT"
    case schemaVersion = "SCHEMA_VERSION"
    case statusCode = "STATUS_CODE"
}

struct OperationalFailureFactV1: Codable, Equatable, Sendable {
    let key: OperationalFailureFactKeyV1
    let value: Int64
}

enum OperationalVersionDispositionV1: String, Codable, Hashable, Sendable {
    case recorded = "RECORDED"
    case unavailable = "UNAVAILABLE"
}

struct OperationalFailureDescriptorV1: Codable, Equatable, Sendable {
    let registryVersion: Int
    let code: OperationalFailureCodeV1
    let domain: OperationalFailureDomainV1
    let severity: OperationalFailureSeverityV1
    let retryability: OperationalRetryabilityV1
    let operation: OperationalOperationV1
    let owner: OperationalOwnerV1
    let primaryAction: OperationalActionV1
    let fallbackAction: OperationalActionV1?
    let helpTopic: OperationalHelpTopicV1?
    let privacyClass: OperationalPrivacyClassV1
}

enum OperationalFailureRegistryV1 {
    static let version = 1

    static let descriptors: [OperationalFailureDescriptorV1] = [
        descriptor(.backupExportFailed, .backup, .error, .retryImmediately, .backupExport, .backup, .retry, .contactSupport, .backup),
        descriptor(.backupRestoreFailed, .backup, .error, .retryImmediately, .backupRestore, .backup, .retry, .contactSupport, .backup),
        descriptor(.backupSourceChanged, .backup, .warning, .retryAfterConditionChanges, .backupExport, .backup, .retry, .cancel, .backup),
        descriptor(.capabilityUnavailable, .capability, .warning, .retryAfterConditionChanges, .supportExport, .supportExport, .retry, .contactSupport, .supportExport),
        descriptor(.concurrentOperation, .concurrency, .warning, .retryAfterConditionChanges, .supportExport, .supportExport, .closeOtherOperation, .cancel, nil),
        descriptor(.contentReadFailed, .content, .error, .retryImmediately, .contentRead, .persistence, .retry, .contactSupport, nil),
        descriptor(.commerceUnavailable, .commerce, .warning, .retryAfterConditionChanges, .commerce, .commerce, .retry, .contactSupport, .commerce),
        descriptor(.corruptOperationalStore, .persistence, .critical, .notRetryable, .diagnosticsRead, .diagnosticsStore, .contactSupport, nil, .diagnosticsReset),
        descriptor(.diagnosticsWriteFailed, .diagnostics, .error, .retryImmediately, .diagnosticsWrite, .diagnosticsStore, .retry, .contactSupport, .diagnosticsReset),
        descriptor(.exportCancelled, .cancellation, .info, .notRetryable, .supportExport, .supportExport, .none, nil, nil),
        descriptor(.exportFailed, .export, .error, .retryImmediately, .supportExport, .supportExport, .retry, .contactSupport, .supportExport),
        descriptor(.interrupted, .cancellation, .warning, .retryImmediately, .bootstrap, .deviceLifecycle, .retry, nil, nil),
        descriptor(.partialSafeState, .persistence, .warning, .notRetryable, .bootstrap, .persistence, .contactSupport, nil, nil),
        descriptor(.permissionDenied, .permission, .warning, .retryAfterConditionChanges, .supportExport, .supportExport, .openSettings, .cancel, .supportExport),
        descriptor(.persistenceMigrationRequired, .persistence, .error, .notRetryable, .migration, .persistence, .restart, .contactSupport, nil),
        descriptor(.protectedDataUnavailable, .protectedData, .warning, .retryAfterConditionChanges, .bootstrap, .deviceLifecycle, .unlockDevice, .retry, nil),
        descriptor(.reportRenderFailed, .report, .error, .retryImmediately, .reportRender, .reporting, .retry, .contactSupport, .reports),
        descriptor(.reportUnavailable, .report, .warning, .retryAfterConditionChanges, .reportAvailability, .reporting, .retry, .contactSupport, .reports),
        descriptor(.requiredFileMissing, .content, .warning, .retryAfterConditionChanges, .fileAccess, .persistence, .chooseFile, .cancel, nil),
        descriptor(.restartRequired, .persistence, .warning, .notRetryable, .bootstrap, .deviceLifecycle, .restart, .contactSupport, nil),
        descriptor(.resumeRequired, .cancellation, .warning, .retryAfterConditionChanges, .resume, .deviceLifecycle, .resume, .cancel, nil),
        descriptor(.storageCapacityInsufficient, .storage, .error, .retryAfterConditionChanges, .supportExport, .scratchStore, .freeStorage, .retry, .storage),
        descriptor(.storageWriteFailed, .storage, .error, .retryImmediately, .diagnosticsWrite, .diagnosticsStore, .retry, .contactSupport, .storage),
        descriptor(.unknown, .diagnostics, .error, .notRetryable, .bootstrap, .diagnosticsStore, .contactSupport, nil, nil),
        descriptor(.userCancelled, .cancellation, .info, .notRetryable, .supportExport, .supportExport, .none, nil, nil),
    ]

    static func descriptor(
        for code: OperationalFailureCodeV1
    ) throws -> OperationalFailureDescriptorV1 {
        let matches = descriptors.filter { $0.code == code }
        guard matches.count == 1, let value = matches.first else {
            throw OperationalDiagnosticsValidationFailureV1.registryMismatch
        }
        return value
    }

    static func validate() throws {
        guard descriptors.count == OperationalFailureCodeV1.allCases.count,
              Set(descriptors.map(\.code)).count == descriptors.count,
              descriptors.allSatisfy({ $0.registryVersion == version }) else {
            throw OperationalDiagnosticsValidationFailureV1.registryMismatch
        }
    }

    private static func descriptor(
        _ code: OperationalFailureCodeV1,
        _ domain: OperationalFailureDomainV1,
        _ severity: OperationalFailureSeverityV1,
        _ retryability: OperationalRetryabilityV1,
        _ operation: OperationalOperationV1,
        _ owner: OperationalOwnerV1,
        _ primary: OperationalActionV1,
        _ fallback: OperationalActionV1?,
        _ help: OperationalHelpTopicV1?
    ) -> OperationalFailureDescriptorV1 {
        OperationalFailureDescriptorV1(
            registryVersion: version,
            code: code,
            domain: domain,
            severity: severity,
            retryability: retryability,
            operation: operation,
            owner: owner,
            primaryAction: primary,
            fallbackAction: fallback,
            helpTopic: help,
            privacyClass: .aggregate
        )
    }
}

/// The application boundaries that may translate a typed subsystem failure
/// into the provisional operational-diagnostics registry. This is deliberately
/// closed: shipping boundary adoption remains deferred to S10.6.
enum OperationalFailureBoundaryV1: String, CaseIterable, Codable, Hashable,
    Sendable {
    case persistence = "PERSISTENCE"
    case content = "CONTENT"
    case report = "REPORT"
    case backup = "BACKUP"
    case permissionFileAuthority = "PERMISSION_FILE_AUTHORITY"
    case commerce = "COMMERCE"
}

/// Maps only module-visible typed errors. An error delivered at the wrong
/// boundary, or an unrecognized error, fails closed to UNKNOWN; descriptions,
/// reflection, localized strings, and NSError codes are never consulted.
enum OperationalFailureMapperV1 {
    static func code(
        for error: any Error,
        at boundary: OperationalFailureBoundaryV1
    ) -> OperationalFailureCodeV1 {
        switch boundary {
        case .persistence:
            if error is StoreMigrationFailure {
                return .persistenceMigrationRequired
            }
            if let failure = error as? StoreGenerationFailure {
                switch failure {
                case .dataPointerInvalid:
                    return .restartRequired
                case .dataGenerationMissing:
                    return .requiredFileMissing
                }
            }
        case .content:
            if error is MediaImportErrorV1 {
                return .contentReadFailed
            }
            if let failure = error as? EvidenceBundleStoreError {
                switch failure {
                case .bundleMissing:
                    return .requiredFileMissing
                case .generationRootInvalid, .unsafePath,
                     .stagingBundleAlreadyExists,
                     .promotedBundleAlreadyExists, .bundleShapeInvalid,
                     .fileTypeInvalid, .canonicalJPEGInvalid,
                     .bundleFactsMismatch, .promotedBundleNotOwned,
                     .fileOperationFailed:
                    return .contentReadFailed
                }
            }
        case .report:
            if error is ReportRenderServiceError {
                return .reportRenderFailed
            }
            if error is ReportHistoryCoordinatorError
                || error is ReportDeliveryCoordinatorError {
                return .reportUnavailable
            }
        case .backup:
            if let failure = error as? BackupExportServiceError {
                switch failure {
                case .contextHasChanges, .stalePreview, .sourceChanged,
                     .generationLeaseLost:
                    return .backupSourceChanged
                case .cancelled:
                    return .userCancelled
                case .insufficientStorage:
                    return .storageCapacityInsufficient
                case .invalidGeneration, .invalidAuthority,
                     .destinationInvalid, .destinationExists, .cleanupFailed,
                     .writeFailed:
                    return .backupExportFailed
                }
            }
            if error is BackupRestoreServiceError {
                return .backupRestoreFailed
            }
            if let failure = error as? BackupImportServiceError {
                switch failure {
                case .securityScopeDenied:
                    return .permissionDenied
                case .invalidGeneration, .coordinationFailed, .invalidSource,
                     .copyFailed, .cleanupFailed:
                    return .backupRestoreFailed
                }
            }
        case .permissionFileAuthority:
            if error is ApplicationFileAuthorityErrorV1 {
                return .permissionDenied
            }
            if let failure = error as? ProtectedFilePolicyError {
                switch failure {
                case .protectedDataUnavailable:
                    return .protectedDataUnavailable
                case .invalidURL, .invalidRelativePath, .missing,
                     .symbolicLink, .invalidType, .hardLink, .identityChanged,
                     .attributeWriteFailed, .resourceValueMismatch:
                    return .permissionDenied
                }
            }
        case .commerce:
            if error is StoreKitProductLoaderError
                || error is EntitlementStoreError {
                return .commerceUnavailable
            }
        }
        return .unknown
    }

    static func failure(
        for error: any Error,
        at boundary: OperationalFailureBoundaryV1,
        occurredAt: Date,
        occurrenceCount: Int64 = 1,
        facts: [OperationalFailureFactV1] = [],
        appVersion: String? = nil,
        appBuild: String? = nil,
        packageVersion: String? = nil
    ) throws -> OperationalFailureV1 {
        try OperationalFailureV1(
            code: code(for: error, at: boundary),
            occurredAt: occurredAt,
            occurrenceCount: occurrenceCount,
            facts: facts,
            appVersion: appVersion,
            appBuild: appBuild,
            packageVersion: packageVersion
        )
    }
}

struct OperationalFailureV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumFactCount = 16

    let schemaVersion: Int
    let descriptor: OperationalFailureDescriptorV1
    let occurredAt: Date
    let occurrenceCount: Int64
    let facts: [OperationalFailureFactV1]
    let versionDisposition: OperationalVersionDispositionV1
    let appVersion: String?
    let appBuild: String?
    let packageVersion: String?

    init(
        code: OperationalFailureCodeV1,
        occurredAt: Date,
        occurrenceCount: Int64 = 1,
        facts: [OperationalFailureFactV1] = [],
        appVersion: String? = nil,
        appBuild: String? = nil,
        packageVersion: String? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        descriptor = try OperationalFailureRegistryV1.descriptor(for: code)
        self.occurredAt = occurredAt
        self.occurrenceCount = occurrenceCount
        self.facts = facts
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.packageVersion = packageVersion
        versionDisposition = appVersion == nil && appBuild == nil
            && packageVersion == nil ? .unavailable : .recorded
        try validate()
    }

    func validate() throws {
        try OperationalFailureRegistryV1.validate()
        guard schemaVersion == Self.schemaVersion,
              descriptor == (try OperationalFailureRegistryV1.descriptor(for: descriptor.code)),
              occurredAt.timeIntervalSinceReferenceDate.isFinite,
              occurrenceCount > 0,
              facts.count <= Self.maximumFactCount,
              Set(facts.map(\.key)).count == facts.count,
              Self.validVersions(
                  disposition: versionDisposition,
                  appVersion: appVersion,
                  appBuild: appBuild,
                  packageVersion: packageVersion
              ) else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
    }

    private static func validVersions(
        disposition: OperationalVersionDispositionV1,
        appVersion: String?,
        appBuild: String?,
        packageVersion: String?
    ) -> Bool {
        let values = [appVersion, appBuild, packageVersion]
        switch disposition {
        case .unavailable:
            return values.allSatisfy { $0 == nil }
        case .recorded:
            return values.allSatisfy {
                $0.map(OperationalDiagnosticsBoundsV1.validVersionValue) ?? false
            }
        }
    }
}

enum SystemHealthStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case degraded = "DEGRADED"
    case healthy = "HEALTHY"
    case unavailable = "UNAVAILABLE"
    case unknown = "UNKNOWN"
}

struct SystemHealthDiagnosticsV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumFailureCount = DeviceOperationalSupportStoreSchemaV2.maximumRecords

    let schemaVersion: Int
    let generatedAt: Date
    let state: SystemHealthStateV1
    let failures: [OperationalFailureV1]
    let metricKit: MetricKitSummaryV1?

    init(
        generatedAt: Date,
        state: SystemHealthStateV1,
        failures: [OperationalFailureV1],
        metricKit: MetricKitSummaryV1?
    ) throws {
        schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.state = state
        self.failures = failures
        self.metricKit = metricKit
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              generatedAt.timeIntervalSinceReferenceDate.isFinite,
              failures.count <= Self.maximumFailureCount,
              metricKit?.isValid ?? true else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
        try failures.forEach { try $0.validate() }
        switch state {
        case .healthy:
            guard failures.isEmpty else {
                throw OperationalDiagnosticsValidationFailureV1.invalidValue
            }
        case .degraded:
            guard !failures.isEmpty else {
                throw OperationalDiagnosticsValidationFailureV1.invalidValue
            }
        case .unavailable, .unknown:
            break
        }
    }
}

struct DeviceOperationalSupportSnapshotV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let health: SystemHealthDiagnosticsV1
    let counters: DiagnosticsV1

    init(health: SystemHealthDiagnosticsV1, counters: DiagnosticsV1) throws {
        schemaVersion = Self.schemaVersion
        self.health = health
        self.counters = counters
        guard counters.isValid else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
        try health.validate()
    }
}

enum DeviceOperationalSupportStoreSchemaV2 {
    static let version = 2
    static let maximumRecordBytes = 16_384
    static let maximumTotalBytes = 524_288
    static let maximumRecords = 128
}

protocol DeviceOperationalSupportStoreV2: Sendable {
    func operationalSupportSnapshot() async throws -> DeviceOperationalSupportSnapshotV2
    func recordOperationalFailure(_ failure: OperationalFailureV1) async throws
    func replaceSystemHealth(_ health: SystemHealthDiagnosticsV1) async throws
    func resetOperationalSupport() async throws
}

enum ScratchDataPurposeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case capture = "CAPTURE"
    case importData = "IMPORT"
    case source = "SOURCE"
    case supportExport = "SUPPORT_EXPORT"

    /// Source-compatible spelling retained for callers written before the
    /// closed registry standardized the persisted value as SUPPORT_EXPORT.
    static var supportBundle: Self { .supportExport }

    var maximumByteCount: UInt64 {
        switch self {
        case .supportExport: return 1_048_576
        case .capture: return 536_870_912
        case .importData, .source: return 4_294_967_296
        }
    }

    var maximumLifetimeSeconds: TimeInterval {
        switch self {
        case .supportExport: return 900
        case .capture: return 7_200
        case .importData, .source: return 14_400
        }
    }
}

enum ScratchDataOwnerV1: String, CaseIterable, Codable, Hashable, Sendable {
    case capture = "CAPTURE"
    case importData = "IMPORT"
    case source = "SOURCE"
    case supportExport = "SUPPORT_EXPORT"
}

enum ScratchDataProtectionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case complete = "COMPLETE"
}

enum ScratchDataBackupPolicyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case excluded = "EXCLUDED"
}

struct ScratchDataLeaseRequestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let leaseID: UUID
    let purpose: ScratchDataPurposeV1
    let owner: ScratchDataOwnerV1
    let ownerOperationID: UUID
    let requestedByteCount: UInt64
    let createdAt: Date
    let expiresAt: Date
    let protection: ScratchDataProtectionV1
    let backupPolicy: ScratchDataBackupPolicyV1

    init(
        leaseID: UUID,
        purpose: ScratchDataPurposeV1,
        owner: ScratchDataOwnerV1,
        ownerOperationID: UUID,
        requestedByteCount: UInt64,
        createdAt: Date,
        expiresAt: Date,
        protection: ScratchDataProtectionV1 = .complete,
        backupPolicy: ScratchDataBackupPolicyV1 = .excluded
    ) throws {
        schemaVersion = Self.schemaVersion
        self.leaseID = leaseID
        self.purpose = purpose
        self.owner = owner
        self.ownerOperationID = ownerOperationID
        self.requestedByteCount = requestedByteCount
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.protection = protection
        self.backupPolicy = backupPolicy
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              requestedByteCount > 0,
              requestedByteCount <= purpose.maximumByteCount,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > createdAt,
              expiresAt.timeIntervalSince(createdAt) <= purpose.maximumLifetimeSeconds,
              Self.ownerMatchesPurpose(owner, purpose),
              backupPolicy == .excluded else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
    }

    private static func ownerMatchesPurpose(
        _ owner: ScratchDataOwnerV1,
        _ purpose: ScratchDataPurposeV1
    ) -> Bool {
        switch (owner, purpose) {
        case (.capture, .capture), (.importData, .importData),
             (.source, .source), (.supportExport, .supportExport):
            return true
        default:
            return false
        }
    }
}

struct ScratchDataLeaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let request: ScratchDataLeaseRequestV1
    let relativeDirectory: String

    init(request: ScratchDataLeaseRequestV1, relativeDirectory: String) throws {
        schemaVersion = Self.schemaVersion
        self.request = request
        self.relativeDirectory = relativeDirectory
        try request.validate()
        guard schemaVersion == Self.schemaVersion,
              OperationalDiagnosticsBoundsV1.validRelativeName(relativeDirectory) else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
    }
}

enum ScratchDataLeaseTerminalV1: String, CaseIterable, Codable, Hashable, Sendable {
    case cancelled = "CANCELLED"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case recoveredExpired = "RECOVERED_EXPIRED"
}

struct ScratchDataLeaseRecoverySummaryV1: Codable, Equatable, Sendable {
    let recoveredExpiredLeaseCount: Int
    let removedByteCount: UInt64

    init(recoveredExpiredLeaseCount: Int, removedByteCount: UInt64) throws {
        self.recoveredExpiredLeaseCount = recoveredExpiredLeaseCount
        self.removedByteCount = removedByteCount
        guard recoveredExpiredLeaseCount >= 0 else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
    }
}

protocol ScratchDataLeasePortV1: Sendable {
    func acquireScratchLease(_ request: ScratchDataLeaseRequestV1) async throws -> ScratchDataLeaseV1
    func writeScratchData(_ data: Data, named: String, lease: ScratchDataLeaseV1) async throws -> URL
    func releaseScratchLease(_ lease: ScratchDataLeaseV1, terminal: ScratchDataLeaseTerminalV1) async throws
    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1
    func resetScratchData() async throws
    func eraseScratchData() async throws
}

enum SupportBundleModeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case bootstrapOnly = "BOOTSTRAP_ONLY"
    case full = "FULL"
}

enum SupportBundleMemberKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case diagnosticSummary = "DIAGNOSTIC_SUMMARY"
    case systemHealth = "SYSTEM_HEALTH"
}

struct SupportBundleManifestEntryV1: Codable, Equatable, Sendable {
    let kind: SupportBundleMemberKindV1
    let relativeName: String
    let byteCount: Int
    let sha256: String

    func validate() throws {
        guard OperationalDiagnosticsBoundsV1.validRelativeName(relativeName),
              byteCount >= 0,
              byteCount <= SupportBundleManifestV1.maximumCanonicalBytes,
              OperationalDiagnosticsBoundsV1.isLowercaseSHA256(sha256) else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
    }
}

struct SupportBundleManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumCanonicalBytes = 524_288
    static let maximumMemberCount = 2

    let schemaVersion: Int
    let bundleID: UUID
    let mode: SupportBundleModeV1
    let generatedAt: Date
    let entries: [SupportBundleManifestEntryV1]
    let totalCanonicalByteCount: Int
    let containsCustomerContent: Bool
    let containsCustomerIdentifier: Bool
    let containsRawLogs: Bool
    let permitsAutomaticUpload: Bool

    init(
        bundleID: UUID,
        mode: SupportBundleModeV1,
        generatedAt: Date,
        entries: [SupportBundleManifestEntryV1],
        totalCanonicalByteCount: Int
    ) throws {
        schemaVersion = Self.schemaVersion
        self.bundleID = bundleID
        self.mode = mode
        self.generatedAt = generatedAt
        self.entries = entries
        self.totalCanonicalByteCount = totalCanonicalByteCount
        containsCustomerContent = false
        containsCustomerIdentifier = false
        containsRawLogs = false
        permitsAutomaticUpload = false
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              generatedAt.timeIntervalSinceReferenceDate.isFinite,
              !entries.isEmpty,
              entries.count <= Self.maximumMemberCount,
              Set(entries.map(\.kind)).count == entries.count,
              Set(entries.map(\.relativeName)).count == entries.count,
              entries.map(\.kind).allSatisfy(Self.allowedMembers(for: mode).contains),
              totalCanonicalByteCount >= 0,
              totalCanonicalByteCount <= Self.maximumCanonicalBytes,
              !containsCustomerContent,
              !containsCustomerIdentifier,
              !containsRawLogs,
              !permitsAutomaticUpload else {
            throw OperationalDiagnosticsValidationFailureV1.privacyViolation
        }
        try entries.forEach { try $0.validate() }
        let aggregate = entries.reduce(0) { partial, entry in
            let (next, overflow) = partial.addingReportingOverflow(entry.byteCount)
            return overflow ? Int.max : next
        }
        guard aggregate == totalCanonicalByteCount else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
    }

    static func allowedMembers(
        for mode: SupportBundleModeV1
    ) -> Set<SupportBundleMemberKindV1> {
        switch mode {
        case .bootstrapOnly: return [.diagnosticSummary]
        case .full: return [.diagnosticSummary, .systemHealth]
        }
    }
}

enum SupportExportDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case cancelled = "CANCELLED"
    case expired = "EXPIRED"
    case failed = "FAILED"
    case prepared = "PREPARED"
    case shared = "SHARED"
}

struct SupportExportResultV1: Equatable, Sendable {
    let disposition: SupportExportDispositionV1
    let manifest: SupportBundleManifestV1?
    let lease: ScratchDataLeaseV1?
    let fileURL: URL?
    private let terminalToken: SupportExportTerminalTokenV1?

    init(
        disposition: SupportExportDispositionV1,
        manifest: SupportBundleManifestV1?,
        lease: ScratchDataLeaseV1?,
        fileURL: URL?
    ) throws {
        self.disposition = disposition
        self.manifest = manifest
        self.lease = lease
        self.fileURL = fileURL
        switch disposition {
        case .cancelled, .expired, .failed:
            guard manifest == nil, lease == nil, fileURL == nil else {
                throw OperationalDiagnosticsValidationFailureV1.invalidValue
            }
            terminalToken = nil
        case .prepared:
            guard let manifest, let lease, fileURL?.isFileURL == true,
                  lease.request.ownerOperationID == manifest.bundleID else {
                throw OperationalDiagnosticsValidationFailureV1.invalidValue
            }
            try manifest.validate()
            try lease.request.validate()
            terminalToken = SupportExportTerminalTokenV1()
        case .shared:
            guard let manifest, lease == nil, fileURL == nil else {
                throw OperationalDiagnosticsValidationFailureV1.invalidValue
            }
            try manifest.validate()
            terminalToken = nil
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.disposition == rhs.disposition
            && lhs.manifest == rhs.manifest
            && lhs.lease == rhs.lease
            && lhs.fileURL == rhs.fileURL
    }

    /// Begins the sole terminal transition. A cleanup failure may retry only
    /// this same disposition; concurrent, changed, or completed claims fail.
    func beginTerminalDisposition(
        _ disposition: SupportExportDispositionV1
    ) -> Bool {
        terminalToken?.begin(disposition) ?? false
    }

    func rollbackTerminalDisposition(
        _ disposition: SupportExportDispositionV1
    ) {
        terminalToken?.rollback(disposition)
    }

    func commitTerminalDisposition(
        _ disposition: SupportExportDispositionV1
    ) {
        terminalToken?.commit(disposition)
    }
}

/// One bounded replay guard owned by one prepared result. Value copies retain
/// this same token; terminal receipts carry no token and release the state.
fileprivate final class SupportExportTerminalTokenV1: @unchecked Sendable {
    private enum State {
        case available
        case inProgress(SupportExportDispositionV1)
        case retryable(SupportExportDispositionV1)
        case finished(SupportExportDispositionV1)
    }

    private let lock = NSLock()
    private var state = State.available

    func begin(_ disposition: SupportExportDispositionV1) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .available:
            state = .inProgress(disposition)
            return true
        case .retryable(let original) where original == disposition:
            state = .inProgress(disposition)
            return true
        case .inProgress, .retryable, .finished:
            return false
        }
    }

    func rollback(_ disposition: SupportExportDispositionV1) {
        lock.lock()
        defer { lock.unlock() }
        guard case .inProgress(let original) = state,
              original == disposition else { return }
        state = .retryable(original)
    }

    func commit(_ disposition: SupportExportDispositionV1) {
        lock.lock()
        defer { lock.unlock() }
        guard case .inProgress(let original) = state,
              original == disposition else { return }
        state = .finished(original)
    }
}

enum WorkflowStateRegistryV1 {
    static let version = 1
    static let states = [
        "APP_LAUNCH", "CHECK_DRAFT", "FINALIZATION", "REPORT_DELIVERY",
        "RESTORE", "SUPPORT_EXPORT",
    ]
}

struct WorkflowFrictionProfileV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let profileID: String
    let declaredStateKeys: [String]
    let recordsCustomerContent: Bool
    let permitsNetwork: Bool

    init(profileID: String, declaredStateKeys: [String]) throws {
        schemaVersion = Self.schemaVersion
        self.profileID = profileID
        self.declaredStateKeys = declaredStateKeys
        recordsCustomerContent = false
        permitsNetwork = false
        guard OperationalDiagnosticsBoundsV1.validToken(profileID),
              declaredStateKeys.count <= 32,
              Set(declaredStateKeys).count == declaredStateKeys.count,
              declaredStateKeys.allSatisfy({ WorkflowStateRegistryV1.states.contains($0) }) else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
    }
}

struct WorkflowFrictionEventV1: Codable, Equatable, Sendable {
    let profileID: String
    let stateKey: String
    let elapsedMilliseconds: Int64

    init(profileID: String, stateKey: String, elapsedMilliseconds: Int64) throws {
        self.profileID = profileID
        self.stateKey = stateKey
        self.elapsedMilliseconds = elapsedMilliseconds
        guard OperationalDiagnosticsBoundsV1.validToken(profileID),
              WorkflowStateRegistryV1.states.contains(stateKey),
              elapsedMilliseconds >= 0 else {
            throw OperationalDiagnosticsValidationFailureV1.invalidValue
        }
    }
}

struct LocalDiagnosticsPreferenceV1: Codable, Equatable, Sendable {
    static let declaration = LocalDiagnosticsPreferenceV1()
    let isEnabled = false
    let productionWritesAllowed = false
    let networkAllowed = false

    private init() {}
}

enum OperationalDiagnosticsBoundsV1 {
    static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0)
            }
    }

    static func validRelativeName(_ value: String) -> Bool {
        validToken(value) && !value.contains("..") && !value.contains("/") && !value.contains("\\")
    }

    static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    static func validVersionValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed == value
            && trimmed.utf8.count <= 128
            && trimmed.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}

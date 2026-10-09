import Darwin
import Foundation
import CryptoKit

enum Counter: Sendable {
    case firstSignCreated
    case onboardingCompleted
    case paywallPresented
    case recheckCompleted
    case reportSaved
    case reportShareSheetPresented
}

enum PurchaseResult: Sendable {
    case cancelled
    case failed
    case pending
    case unverified
    case verified
}

struct PurchaseResultHistogram: Codable, Equatable, Sendable {
    var cancelled: Int64
    var failed: Int64
    var pending: Int64
    var unverified: Int64
    var verified: Int64

    static let zero = PurchaseResultHistogram(
        cancelled: 0,
        failed: 0,
        pending: 0,
        unverified: 0,
        verified: 0
    )
}

struct DiagnosticsV1: Codable, Equatable, Sendable {
    var firstSignCreated: Int64
    var onboardingCompleted: Int64
    var paywallPresented: Int64
    var purchaseResult: PurchaseResultHistogram
    var recheckCompleted: Int64
    var reportSaved: Int64
    var reportShareSheetPresented: Int64
    var schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case firstSignCreated = "first_sign_created"
        case onboardingCompleted = "onboarding_completed"
        case paywallPresented = "paywall_presented"
        case purchaseResult = "purchase_result"
        case recheckCompleted = "recheck_completed"
        case reportSaved = "report_saved"
        case reportShareSheetPresented = "report_share_sheet_presented"
        case schemaVersion
    }

    static let zero = DiagnosticsV1(
        firstSignCreated: 0,
        onboardingCompleted: 0,
        paywallPresented: 0,
        purchaseResult: .zero,
        recheckCompleted: 0,
        reportSaved: 0,
        reportShareSheetPresented: 0,
        schemaVersion: 1
    )

    var isValid: Bool {
        schemaVersion == 1
            && firstSignCreated >= 0
            && onboardingCompleted >= 0
            && paywallPresented >= 0
            && purchaseResult.cancelled >= 0
            && purchaseResult.failed >= 0
            && purchaseResult.pending >= 0
            && purchaseResult.unverified >= 0
            && purchaseResult.verified >= 0
            && recheckCompleted >= 0
            && reportSaved >= 0
            && reportShareSheetPresented >= 0
    }
}

private struct DeviceOperationalSupportEnvelopeV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let health: SystemHealthDiagnosticsV1
    let counters: DiagnosticsV1

    init(health: SystemHealthDiagnosticsV1, counters: DiagnosticsV1) throws {
        schemaVersion = Self.schemaVersion
        self.health = health
        self.counters = counters
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, counters.isValid else {
            throw DiagnosticsFailure.invalidFile
        }
        try health.validate()
    }
}

private struct DeviceOperationalSupportEnvelopeV3: Codable, Equatable, Sendable {
    static let schemaVersion = 3
    let schemaVersion: Int
    let health: SystemHealthDiagnosticsV1
    let counters: DiagnosticsV1
    let feedbackDraft: SupportFeedbackDraftV1?
    let feedbackDraftRecoveryRequired: Bool

    init(
        health: SystemHealthDiagnosticsV1,
        counters: DiagnosticsV1,
        feedbackDraft: SupportFeedbackDraftV1?,
        feedbackDraftRecoveryRequired: Bool
    ) throws {
        schemaVersion = Self.schemaVersion
        self.health = health
        self.counters = counters
        self.feedbackDraft = feedbackDraft
        self.feedbackDraftRecoveryRequired = feedbackDraftRecoveryRequired
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, counters.isValid else {
            throw DiagnosticsFailure.invalidFile
        }
        try health.validate()
        try feedbackDraft?.validate()
        guard !feedbackDraftRecoveryRequired || feedbackDraft == nil else {
            throw DiagnosticsFailure.invalidFile
        }
    }
}

actor DiagnosticsStore: DeviceOperationalSupportStoreV3 {
    /// Process-wide serialization for the sole device-operational support
    /// format. Per-instance actor isolation alone cannot serialize two store
    /// handles opened against the same application-support root.
    private static let formatLease = NSRecursiveLock()
    static let maximumOperationalRecordBytes =
        DeviceOperationalSupportStoreSchemaV3.maximumRecordBytes
    static let maximumOperationalTotalBytes =
        DeviceOperationalSupportStoreSchemaV3.maximumTotalBytes
    static let maximumOperationalRecords =
        DeviceOperationalSupportStoreSchemaV3.maximumRecords
    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let linkCount: UInt64
        let size: Int64

        init(_ information: stat) {
            device = UInt64(information.st_dev)
            inode = UInt64(information.st_ino)
            linkCount = UInt64(information.st_nlink)
            size = Int64(information.st_size)
        }
    }

    private struct DirectoryIdentity: Equatable {
        let device: UInt64
        let inode: UInt64

        init(_ information: stat) throws {
            guard (information.st_mode & S_IFMT) == S_IFDIR else {
                throw DiagnosticsFailure.invalidFile
            }
            device = UInt64(information.st_dev)
            inode = UInt64(information.st_ino)
        }
    }

    private final class PinnedDiagnosticsAuthority {
        let applicationSupportDescriptor: Int32
        let diagnosticsDescriptor: Int32
        let applicationSupportIdentity: DirectoryIdentity
        let diagnosticsIdentity: DirectoryIdentity
        private let applicationSupportURL: URL
        private let diagnosticsName: String

        private init(
            applicationSupportDescriptor: Int32,
            diagnosticsDescriptor: Int32,
            applicationSupportIdentity: DirectoryIdentity,
            diagnosticsIdentity: DirectoryIdentity,
            applicationSupportURL: URL,
            diagnosticsName: String
        ) {
            self.applicationSupportDescriptor = applicationSupportDescriptor
            self.diagnosticsDescriptor = diagnosticsDescriptor
            self.applicationSupportIdentity = applicationSupportIdentity
            self.diagnosticsIdentity = diagnosticsIdentity
            self.applicationSupportURL = applicationSupportURL
            self.diagnosticsName = diagnosticsName
        }

        deinit {
            _ = Darwin.close(diagnosticsDescriptor)
            _ = Darwin.close(applicationSupportDescriptor)
        }

        static func open(
            applicationSupportURL: URL,
            diagnosticsURL: URL,
            fileManager: FileManager,
            createIfMissing: Bool
        ) throws -> PinnedDiagnosticsAuthority? {
            #if DEBUG
            var diagnosticBoundary = "application-support-create"
            var diagnosticFailed = true
            defer {
                if diagnosticFailed {
                    print("Diagnostics authority lastBoundary=\(diagnosticBoundary)")
                }
            }
            #endif
            if createIfMissing {
                try fileManager.createDirectory(
                    at: applicationSupportURL,
                    withIntermediateDirectories: true
                )
            }
            #if DEBUG
            diagnosticBoundary = "application-support-open"
            #endif
            let applicationSupportDescriptor = Darwin.open(
                applicationSupportURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if applicationSupportDescriptor < 0 {
                if !createIfMissing, errno == ENOENT {
                    #if DEBUG
                    diagnosticFailed = false
                    #endif
                    return nil
                }
                throw DiagnosticsFailure.invalidFile
            }
            var ownsApplicationSupport = true
            defer {
                if ownsApplicationSupport {
                    _ = Darwin.close(applicationSupportDescriptor)
                }
            }
            #if DEBUG
            diagnosticBoundary = "application-support-stat"
            #endif
            var applicationSupportInformation = stat()
            guard Darwin.fstat(
                applicationSupportDescriptor,
                &applicationSupportInformation
            ) == 0 else {
                throw DiagnosticsFailure.invalidFile
            }
            let applicationSupportIdentity = try DirectoryIdentity(
                applicationSupportInformation
            )
            let diagnosticsName = diagnosticsURL.lastPathComponent
            #if DEBUG
            diagnosticBoundary = "diagnostics-relationship"
            #endif
            guard !diagnosticsName.isEmpty,
                  diagnosticsURL.deletingLastPathComponent()
                    .standardizedFileURL == applicationSupportURL.standardizedFileURL else {
                throw DiagnosticsFailure.invalidFile
            }
            #if DEBUG
            diagnosticBoundary = "diagnostics-open"
            #endif
            var diagnosticsDescriptor = Darwin.openat(
                applicationSupportDescriptor,
                diagnosticsName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if diagnosticsDescriptor < 0, errno == ENOENT {
                guard createIfMissing else {
                    #if DEBUG
                    diagnosticFailed = false
                    #endif
                    return nil
                }
                #if DEBUG
                diagnosticBoundary = "diagnostics-mkdir"
                #endif
                guard Darwin.mkdirat(
                    applicationSupportDescriptor,
                    diagnosticsName,
                    mode_t(0o700)
                ) == 0 || errno == EEXIST else {
                    throw DiagnosticsFailure.invalidFile
                }
                #if DEBUG
                diagnosticBoundary = "application-support-sync-after-mkdir"
                #endif
                guard Darwin.fsync(applicationSupportDescriptor) == 0 else {
                    throw DiagnosticsFailure.invalidFile
                }
                #if DEBUG
                diagnosticBoundary = "diagnostics-reopen"
                #endif
                diagnosticsDescriptor = Darwin.openat(
                    applicationSupportDescriptor,
                    diagnosticsName,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
            }
            guard diagnosticsDescriptor >= 0 else {
                throw DiagnosticsFailure.invalidFile
            }
            var ownsDiagnostics = true
            defer {
                if ownsDiagnostics { _ = Darwin.close(diagnosticsDescriptor) }
            }
            #if DEBUG
            diagnosticBoundary = "diagnostics-stat"
            #endif
            var diagnosticsInformation = stat()
            guard Darwin.fstat(
                diagnosticsDescriptor,
                &diagnosticsInformation
            ) == 0 else {
                throw DiagnosticsFailure.invalidFile
            }
            let diagnosticsIdentity = try DirectoryIdentity(
                diagnosticsInformation
            )
            let authority = PinnedDiagnosticsAuthority(
                applicationSupportDescriptor: applicationSupportDescriptor,
                diagnosticsDescriptor: diagnosticsDescriptor,
                applicationSupportIdentity: applicationSupportIdentity,
                diagnosticsIdentity: diagnosticsIdentity,
                applicationSupportURL: applicationSupportURL.standardizedFileURL,
                diagnosticsName: diagnosticsName
            )
            ownsApplicationSupport = false
            ownsDiagnostics = false
            #if DEBUG
            diagnosticFailed = false
            #endif
            return authority
        }

        func verify() throws {
            var applicationSupportInformation = stat()
            guard Darwin.fstat(
                applicationSupportDescriptor,
                &applicationSupportInformation
            ) == 0,
                  try DirectoryIdentity(applicationSupportInformation)
                    == applicationSupportIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            var diagnosticsInformation = stat()
            guard Darwin.fstat(
                diagnosticsDescriptor,
                &diagnosticsInformation
            ) == 0,
                  try DirectoryIdentity(diagnosticsInformation)
                    == diagnosticsIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            var childInformation = stat()
            guard Darwin.fstatat(
                applicationSupportDescriptor,
                diagnosticsName,
                &childInformation,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
                  try DirectoryIdentity(childInformation)
                    == diagnosticsIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            let reopenedApplicationSupport = Darwin.open(
                applicationSupportURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard reopenedApplicationSupport >= 0 else {
                throw DiagnosticsFailure.invalidFile
            }
            defer { _ = Darwin.close(reopenedApplicationSupport) }
            var reopenedInformation = stat()
            guard Darwin.fstat(
                reopenedApplicationSupport,
                &reopenedInformation
            ) == 0,
                  try DirectoryIdentity(reopenedInformation)
                    == applicationSupportIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            let reopenedDiagnostics = Darwin.openat(
                reopenedApplicationSupport,
                diagnosticsName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard reopenedDiagnostics >= 0 else {
                throw DiagnosticsFailure.invalidFile
            }
            defer { _ = Darwin.close(reopenedDiagnostics) }
            var reopenedDiagnosticsInformation = stat()
            guard Darwin.fstat(
                reopenedDiagnostics,
                &reopenedDiagnosticsInformation
            ) == 0,
                  try DirectoryIdentity(reopenedDiagnosticsInformation)
                    == diagnosticsIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
        }
    }

    private static let temporaryName = ".counters.json.next"
    private static let backupName = ".counters.json.previous"
    private static let quarantineName = ".counters.json.quarantine"

    private let applicationSupportURL: URL
    private let directoryURL: URL
    private let countersURL: URL
    private let fileManager: FileManager
    private let logger: DiagnosticsLogger
    private let now: @Sendable () -> Date
    private let storagePreflight: StoragePreflightService
    private var counters = DiagnosticsV1.zero
    private var health: SystemHealthDiagnosticsV1?
    private var feedbackDraft: SupportFeedbackDraftV1?
    private var feedbackDraftRecoveryRequired = false
    private var lastCommittedData: Data?
    private var isPrepared = false
    private var preparationFailure: DiagnosticsFailure?

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        logger: DiagnosticsLogger = .live,
        now: @escaping @Sendable () -> Date = Date.init,
        capacityProvider: @escaping StoragePreflightService.CapacityProvider = {
            try $0.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        }
    ) {
        let directoryURL = applicationSupportURL.appendingPathComponent(
            "FieldEvidenceDiagnostics",
            isDirectory: true
        )
        self.applicationSupportURL = directoryURL.deletingLastPathComponent()
        self.directoryURL = directoryURL
        self.countersURL = directoryURL.appendingPathComponent(
            "counters.json",
            isDirectory: false
        )
        self.fileManager = fileManager
        self.logger = logger
        self.now = now
        self.storagePreflight = StoragePreflightService(
            capacityProvider: capacityProvider
        )
        self.health = nil
        self.feedbackDraft = nil
    }

    func prepare() {
        guard !isPrepared else {
            return
        }
        do {
            try recoverPendingPublication()
            guard let authority = try PinnedDiagnosticsAuthority.open(
                applicationSupportURL: applicationSupportURL,
                diagnosticsURL: directoryURL,
                fileManager: fileManager,
                createIfMissing: false
            ) else {
                let initialHealth = try emptyHealth()
                guard persist(.zero, health: initialHealth) else { return }
                counters = .zero
                health = initialHealth
                isPrepared = true
                preparationFailure = nil
                return
            }
            let authorityCheck = { try authority.verify() }
            try authorityCheck()
            guard let identity = try fileIdentityIfPresent(
                at: countersURL,
                authorityCheck: authorityCheck
            ) else {
                let initialHealth = try emptyHealth()
                guard persist(.zero, health: initialHealth) else { return }
                counters = .zero
                health = initialHealth
                isPrepared = true
                preparationFailure = nil
                return
            }
            do {
                try authorityCheck()
                try ProtectedFilePolicyV1.verify(.diagnostics, at: countersURL)
                try authorityCheck()
            } catch let failure as ProtectedFilePolicyError
                where failure == .resourceValueMismatch {
                let data = try readData(
                    at: countersURL,
                    expected: identity,
                    authorityCheck: authorityCheck
                )
                let decoded = try decodeOperationalStore(data)
                try ProtectedFilePolicyV1.applyAndVerify(
                    .diagnostics,
                    at: countersURL,
                    authorityCheck: authorityCheck
                )
                try syncFile(
                    at: countersURL,
                    expected: identity,
                    authorityCheck: authorityCheck
                )
                counters = decoded.counters
                health = decoded.health
                lastCommittedData = data
                isPrepared = true
                preparationFailure = nil
                feedbackDraft = decoded.feedbackDraft
                feedbackDraftRecoveryRequired = decoded.feedbackDraftRecoveryRequired
                if !isV3Envelope(data) {
                    guard persist(counters, health: decoded.health) else {
                        isPrepared = false
                        return
                    }
                }
                return
            }
            let data = try readData(
                at: countersURL,
                expected: identity,
                authorityCheck: authorityCheck
            )
            let decoded = try decodeOperationalStore(data)
            counters = decoded.counters
            health = decoded.health
            lastCommittedData = data
            feedbackDraft = decoded.feedbackDraft
            feedbackDraftRecoveryRequired = decoded.feedbackDraftRecoveryRequired
            isPrepared = true
            preparationFailure = nil
            if !isV3Envelope(data) {
                guard persist(counters, health: decoded.health) else {
                    isPrepared = false
                    return
                }
            }
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            preparationFailure = .protectedDataUnavailable
            logger.record(DiagnosticsLogEvent.countersWriteFailed)
        } catch DiagnosticsFailure.unsupportedVersion {
            // A newer writer owns these bytes. Downgrade never destroys or
            // rewrites them; a compatible forward upgrade is required.
            preparationFailure = .unsupportedVersion
            logger.record(DiagnosticsLogEvent.countersWriteFailed)
        } catch DiagnosticsFailure.recoveryRequired {
            logger.record(DiagnosticsLogEvent.countersWriteFailed)
            // Quarantine the unreadable bytes, recreate the operational file,
            // and persist the visible recovery-required state. The draft is
            // never represented as empty success while its safe copy exists.
            let candidate = try? emptyHealth()
            if let candidate,
               persist(
                   .zero,
                   health: candidate,
                   feedbackDraft: .some(nil),
                   feedbackDraftRecoveryRequired: true,
                   repairExisting: true
               ) {
                counters = .zero
                health = candidate
                feedbackDraft = nil
                feedbackDraftRecoveryRequired = true
                isPrepared = true
                preparationFailure = nil
            } else {
                preparationFailure = .recoveryRequired
            }
        } catch {
            logger.record(DiagnosticsLogEvent.invalidCountersReset)
            if persist(.zero, repairExisting: true) {
                counters = .zero
                isPrepared = true
                preparationFailure = nil
            } else {
                preparationFailure = .invalidFile
            }
        }
    }

    func snapshot() -> DiagnosticsV1 {
        prepare()
        return counters
    }

    func acceptDescriptorErasedZero() {
        counters = .zero
        do {
            health = try emptyHealth()
            feedbackDraft = nil
            feedbackDraftRecoveryRequired = false
            lastCommittedData = nil
            isPrepared = true
            preparationFailure = nil
        } catch {
            health = nil
            isPrepared = false
            preparationFailure = .invalidFile
        }
    }

    func isExactlyZero() -> Bool {
        prepare()
        return counters == .zero
            && health?.state == .unknown
            && health?.failures.isEmpty == true
            && health?.metricKit == nil
            && feedbackDraft == nil
            && !feedbackDraftRecoveryRequired
    }

    func operationalSupportSnapshot() async throws -> DeviceOperationalSupportSnapshotV2 {
        prepare()
        guard isPrepared, let health else {
            throw preparationFailure ?? DiagnosticsFailure.invalidFile
        }
        return try DeviceOperationalSupportSnapshotV2(health: health, counters: counters)
    }

    /// Internal verification bytes for lifecycle owners that must compare the
    /// physical file against the actual current schema. This deliberately does
    /// not expose the private envelope type or provide another encoder.
    func canonicalOperationalSupportEnvelopeDataV3() async throws -> Data {
        prepare()
        guard isPrepared, let health else {
            throw preparationFailure ?? DiagnosticsFailure.invalidFile
        }
        let envelope = try DeviceOperationalSupportEnvelopeV3(
            health: health,
            counters: counters,
            feedbackDraft: feedbackDraft,
            feedbackDraftRecoveryRequired: feedbackDraftRecoveryRequired
        )
        let data = try canonicalData(for: envelope)
        guard data.count <= Self.maximumOperationalTotalBytes else {
            throw DiagnosticsFailure.sizeLimitExceeded
        }
        return data
    }

    func recordOperationalFailure(_ failure: OperationalFailureV1) async throws {
        prepare()
        guard isPrepared, let health else {
            throw preparationFailure ?? DiagnosticsFailure.invalidFile
        }
        try failure.validate()
        let recordBytes = try canonicalRecordData(failure)
        guard recordBytes.count <= Self.maximumOperationalRecordBytes else {
            throw DiagnosticsFailure.sizeLimitExceeded
        }
        var failures = health.failures
        failures.append(failure)
        if failures.count > Self.maximumOperationalRecords {
            failures.removeFirst(failures.count - Self.maximumOperationalRecords)
        }
        let candidate = try SystemHealthDiagnosticsV1(
            generatedAt: now(),
            state: .degraded,
            failures: failures,
            metricKit: health.metricKit
        )
        guard persist(counters, health: candidate) else {
            throw DiagnosticsFailure.invalidFile
        }
        self.health = candidate
    }

    /// Runs an operation whose declared result is `Never`, records its typed
    /// failure, then rethrows it. A diagnostics-write failure is propagated
    /// instead, so neither the underlying operation nor persistence failure can
    /// be converted into an empty success.
    func recordAndRethrowOperationalFailure(
        at boundary: OperationalFailureBoundaryV1,
        occurrenceCount: Int64 = 1,
        facts: [OperationalFailureFactV1] = [],
        appVersion: String? = nil,
        appBuild: String? = nil,
        packageVersion: String? = nil,
        operation: @Sendable () async throws -> Never
    ) async throws -> Never {
        do {
            return try await operation()
        } catch {
            let failure = try OperationalFailureMapperV1.failure(
                for: error,
                at: boundary,
                occurredAt: now(),
                occurrenceCount: occurrenceCount,
                facts: facts,
                appVersion: appVersion,
                appBuild: appBuild,
                packageVersion: packageVersion
            )
            try await recordOperationalFailure(failure)
            throw error
        }
    }

    func replaceSystemHealth(_ candidate: SystemHealthDiagnosticsV1) async throws {
        prepare()
        guard isPrepared else { throw preparationFailure ?? DiagnosticsFailure.invalidFile }
        try candidate.validate()
        for failure in candidate.failures {
            guard try canonicalRecordData(failure).count
                    <= Self.maximumOperationalRecordBytes else {
                throw DiagnosticsFailure.sizeLimitExceeded
            }
        }
        guard persist(counters, health: candidate) else {
            throw DiagnosticsFailure.invalidFile
        }
        health = candidate
    }

    func resetOperationalSupport() async throws {
        prepare()
        let isExplicitRecoveryReset = preparationFailure == .recoveryRequired
            || feedbackDraftRecoveryRequired
        guard isPrepared || isExplicitRecoveryReset else {
            throw preparationFailure ?? DiagnosticsFailure.invalidFile
        }
        let candidate = try emptyHealth()
        if preparationFailure == .recoveryRequired {
            guard persist(
                .zero,
                health: candidate,
                feedbackDraft: .some(nil),
                feedbackDraftRecoveryRequired: true,
                repairExisting: true
            ) else { throw DiagnosticsFailure.invalidFile }
            counters = .zero
            health = candidate
            feedbackDraft = nil
            feedbackDraftRecoveryRequired = true
            isPrepared = true
            preparationFailure = nil
        }
        if isExplicitRecoveryReset {
            try removeFeedbackRecoveryCopyIfPresent()
        }
        guard persist(
            .zero,
            health: candidate,
            feedbackDraft: .some(nil),
            feedbackDraftRecoveryRequired: false,
            repairExisting: false
        ) else {
            throw DiagnosticsFailure.invalidFile
        }
        counters = .zero
        health = candidate
        feedbackDraft = nil
        feedbackDraftRecoveryRequired = false
        isPrepared = true
        preparationFailure = nil
    }

    func supportFeedbackDraftSnapshot() async throws -> SupportFeedbackDraftStoreSnapshotV1 {
        prepare()
        if preparationFailure == .recoveryRequired || feedbackDraftRecoveryRequired {
            return try SupportFeedbackDraftStoreSnapshotV1(
                state: .recoveryRequired,
                draft: nil,
                safeCopyAvailable: (try? feedbackRecoveryCopyExists()) == true
            )
        }
        guard isPrepared else {
            throw preparationFailure ?? DiagnosticsFailure.invalidFile
        }
        if let feedbackDraft {
            return try SupportFeedbackDraftStoreSnapshotV1(
                state: .available,
                draft: feedbackDraft,
                safeCopyAvailable: false
            )
        }
        return try SupportFeedbackDraftStoreSnapshotV1(
            state: .empty,
            draft: nil,
            safeCopyAvailable: false
        )
    }

    func supportFeedbackRecoveryCopy() async throws -> Data? {
        prepare()
        guard preparationFailure == .recoveryRequired || feedbackDraftRecoveryRequired else {
            return nil
        }
        guard let authority = try PinnedDiagnosticsAuthority.open(
            applicationSupportURL: applicationSupportURL,
            diagnosticsURL: directoryURL,
            fileManager: fileManager,
            createIfMissing: false
        ) else { return nil }
        let authorityCheck = { try authority.verify() }
        let url = directoryURL.appendingPathComponent(
            Self.quarantineName,
            isDirectory: false
        )
        guard let identity = try fileIdentityIfPresent(
            at: url,
            authorityCheck: authorityCheck
        ) else { return nil }
        try ProtectedFilePolicyV1.verify(.diagnostics, at: url)
        let data = try readData(
            at: url,
            expected: identity,
            authorityCheck: authorityCheck
        )
        guard data.count <= Self.maximumOperationalTotalBytes else {
            throw DiagnosticsFailure.sizeLimitExceeded
        }
        return data
    }

    func saveSupportFeedbackDraft(
        _ draft: SupportFeedbackDraftV1,
        expectedRevision: UInt64?
    ) async throws {
        prepare()
        guard isPrepared else {
            throw preparationFailure ?? DiagnosticsFailure.invalidFile
        }
        try draft.validate()
        guard !feedbackDraftRecoveryRequired else {
            throw DiagnosticsFailure.recoveryRequired
        }
        let record = try canonicalData(for: draft)
        guard record.count <= DeviceOperationalSupportStoreSchemaV3.maximumRecordBytes else {
            throw DiagnosticsFailure.sizeLimitExceeded
        }
        switch (feedbackDraft, expectedRevision) {
        case (nil, nil):
            guard draft.revision == 1 else { throw DiagnosticsFailure.concurrentMutation }
        case let (current?, expected?):
            let (next, overflow) = expected.addingReportingOverflow(1)
            guard !overflow,
                  current.draftID == draft.draftID,
                  current.revision == expected,
                  draft.revision == next,
                  draft.createdAt == current.createdAt,
                  draft.updatedAt >= current.updatedAt else {
                throw DiagnosticsFailure.concurrentMutation
            }
        default:
            throw DiagnosticsFailure.concurrentMutation
        }
        guard persist(counters, health: health, feedbackDraft: .some(draft)) else {
            throw DiagnosticsFailure.invalidFile
        }
        feedbackDraft = draft
    }

    func discardSupportFeedbackDraft(
        expectedDraftID: UUID,
        expectedRevision: UInt64
    ) async throws {
        prepare()
        guard isPrepared, let current = feedbackDraft,
              current.draftID == expectedDraftID,
              current.revision == expectedRevision else {
            throw preparationFailure ?? DiagnosticsFailure.concurrentMutation
        }
        guard persist(counters, health: health, feedbackDraft: .some(nil)) else {
            throw DiagnosticsFailure.invalidFile
        }
        feedbackDraft = nil
    }

    func increment(_ counter: Counter) {
        prepare()
        guard isPrepared else { return }
        var candidate = counters

        switch counter {
        case .firstSignCreated:
            candidate.firstSignCreated = incremented(candidate.firstSignCreated)
        case .onboardingCompleted:
            candidate.onboardingCompleted = incremented(candidate.onboardingCompleted)
        case .paywallPresented:
            candidate.paywallPresented = incremented(candidate.paywallPresented)
        case .recheckCompleted:
            candidate.recheckCompleted = incremented(candidate.recheckCompleted)
        case .reportSaved:
            candidate.reportSaved = incremented(candidate.reportSaved)
        case .reportShareSheetPresented:
            candidate.reportShareSheetPresented = incremented(
                candidate.reportShareSheetPresented
            )
        }

        if persist(candidate) {
            counters = candidate
            isPrepared = true
        }
    }

    func incrementPurchaseResult(_ result: PurchaseResult) {
        prepare()
        guard isPrepared else { return }
        var candidate = counters

        switch result {
        case .cancelled:
            candidate.purchaseResult.cancelled = incremented(
                candidate.purchaseResult.cancelled
            )
        case .failed:
            candidate.purchaseResult.failed = incremented(
                candidate.purchaseResult.failed
            )
        case .pending:
            candidate.purchaseResult.pending = incremented(
                candidate.purchaseResult.pending
            )
        case .unverified:
            candidate.purchaseResult.unverified = incremented(
                candidate.purchaseResult.unverified
            )
        case .verified:
            candidate.purchaseResult.verified = incremented(
                candidate.purchaseResult.verified
            )
        }

        if persist(candidate) {
            counters = candidate
            isPrepared = true
        }
    }

    private func persist(
        _ candidate: DiagnosticsV1,
        health healthCandidate: SystemHealthDiagnosticsV1? = nil,
        feedbackDraft feedbackDraftCandidate: SupportFeedbackDraftV1?? = nil,
        feedbackDraftRecoveryRequired recoveryCandidate: Bool? = nil,
        repairExisting: Bool = false
    ) -> Bool {
        Self.formatLease.lock()
        defer { Self.formatLease.unlock() }
        let temporaryURL = directoryURL.appendingPathComponent(
            Self.temporaryName,
            isDirectory: false
        )
        let backupURL = directoryURL.appendingPathComponent(
            Self.backupName,
            isDirectory: false
        )
        let quarantineURL = directoryURL.appendingPathComponent(
            Self.quarantineName,
            isDirectory: false
        )
        var temporaryIdentity: FileIdentity?
        var replacementIdentity: FileIdentity?
        var oldIdentity: FileIdentity?
        var didPublish = false
        var authority: PinnedDiagnosticsAuthority?
        #if DEBUG
        var diagnosticBoundary = "authority-open"
        #endif
        do {
            guard let openedAuthority = try PinnedDiagnosticsAuthority.open(
                applicationSupportURL: applicationSupportURL,
                diagnosticsURL: directoryURL,
                fileManager: fileManager,
                createIfMissing: true
            ) else {
                throw DiagnosticsFailure.invalidFile
            }
            authority = openedAuthority
            let authorityCheck = { try openedAuthority.verify() }
            try authorityCheck()
            #if DEBUG
            diagnosticBoundary = "staging-directory-protection"
            #endif
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                at: directoryURL,
                authorityCheck: authorityCheck
            )
            #if DEBUG
            diagnosticBoundary = "envelope-encode"
            #endif
            let state = try DeviceOperationalSupportEnvelopeV3(
                health: try resolvedHealth(healthCandidate),
                counters: candidate,
                feedbackDraft: feedbackDraftCandidate ?? feedbackDraft,
                feedbackDraftRecoveryRequired: recoveryCandidate
                    ?? feedbackDraftRecoveryRequired
            )
            let data = try canonicalData(for: state)
            let privacyState = try DeviceOperationalSupportEnvelopeV2(
                health: state.health,
                counters: state.counters
            )
            try C54EncryptedPortableEnvelopeDiagnosticPrivacyBoundaryV1.validate(
                canonicalData(for: privacyState)
            )
            guard data.count <= Self.maximumOperationalTotalBytes else {
                throw DiagnosticsFailure.sizeLimitExceeded
            }
            #if DEBUG
            diagnosticBoundary = "capacity-preflight"
            #endif
            try storagePreflight.checkDeviceOperationalWrite(
                byteCount: UInt64(data.count),
                onVolumeContaining: directoryURL
            )

            if let existing = try fileIdentityIfPresent(
                at: temporaryURL,
                authorityCheck: authorityCheck
            ) {
                _ = try readData(
                    at: temporaryURL,
                    expected: existing,
                    authorityCheck: authorityCheck
                )
                try removeOwnedFile(
                    at: temporaryURL,
                    expected: existing,
                    authorityCheck: authorityCheck
                )
            }
            #if DEBUG
            diagnosticBoundary = "temporary-write"
            #endif
            try authorityCheck()
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try authorityCheck()
            temporaryIdentity = try fileIdentity(
                at: temporaryURL,
                authorityCheck: authorityCheck
            )
            guard let temporaryIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            #if DEBUG
            diagnosticBoundary = "temporary-sync"
            #endif
            try syncFile(
                at: temporaryURL,
                expected: temporaryIdentity,
                authorityCheck: authorityCheck
            )
            #if DEBUG
            diagnosticBoundary = "temporary-protection"
            #endif
            try ProtectedFilePolicyV1.applyAndVerify(
                .temporaryFile,
                at: temporaryURL,
                authorityCheck: authorityCheck
            )
            try syncFile(
                at: temporaryURL,
                expected: temporaryIdentity,
                authorityCheck: authorityCheck
            )

            oldIdentity = try fileIdentityIfPresent(
                at: countersURL,
                authorityCheck: authorityCheck
            )
            #if DEBUG
            diagnosticBoundary = "existing-readback"
            #endif
            if !repairExisting {
                switch (oldIdentity, lastCommittedData) {
                case let (identity?, expected?):
                    guard try readData(
                        at: countersURL,
                        expected: identity,
                        authorityCheck: authorityCheck
                    ) == expected else {
                        throw DiagnosticsFailure.concurrentMutation
                    }
                case (nil, nil):
                    break
                default:
                    throw DiagnosticsFailure.concurrentMutation
                }
            }
            if let oldIdentity {
                if !repairExisting {
                    try authorityCheck()
                    try ProtectedFilePolicyV1.verify(
                        .diagnostics,
                        at: countersURL
                    )
                    try authorityCheck()
                }
                guard try fileIdentityIfPresent(
                    at: countersURL,
                    authorityCheck: authorityCheck
                ) == oldIdentity else {
                    throw DiagnosticsFailure.invalidFile
                }
                #if DEBUG
                diagnosticBoundary = "existing-replace"
                #endif
                if let staleBackup = try fileIdentityIfPresent(
                    at: backupURL,
                    authorityCheck: authorityCheck
                ) {
                    try removeOwnedFile(
                        at: backupURL,
                        expected: staleBackup,
                        authorityCheck: authorityCheck
                    )
                    try syncDirectory(authorityCheck: authorityCheck)
                }
                try authorityCheck()
                try fileManager.replaceItemAt(
                    countersURL,
                    withItemAt: temporaryURL,
                    backupItemName: Self.backupName,
                    options: [.withoutDeletingBackupItem]
                )
                try authorityCheck()
                guard let publishedBackupIdentity = try fileIdentityIfPresent(
                    at: backupURL,
                    authorityCheck: authorityCheck
                ) else {
                    throw DiagnosticsFailure.invalidFile
                }
                try ProtectedFilePolicyV1.applyAndVerify(
                    .temporaryFile,
                    at: backupURL,
                    authorityCheck: authorityCheck
                )
                guard try fileIdentityIfPresent(
                    at: backupURL,
                    authorityCheck: authorityCheck
                ) == publishedBackupIdentity else {
                    throw DiagnosticsFailure.invalidFile
                }
            } else {
                #if DEBUG
                diagnosticBoundary = "fresh-move"
                #endif
                guard try fileIdentityIfPresent(
                    at: countersURL,
                    authorityCheck: authorityCheck
                ) == nil else {
                    throw DiagnosticsFailure.invalidFile
                }
                try authorityCheck()
                try fileManager.moveItem(at: temporaryURL, to: countersURL)
            }
            didPublish = true
            #if DEBUG
            diagnosticBoundary = "replacement-identity"
            #endif
            try authorityCheck()
            replacementIdentity = try fileIdentity(
                at: countersURL,
                authorityCheck: authorityCheck
            )
            guard let replacementIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            #if DEBUG
            diagnosticBoundary = "replacement-protection"
            #endif
            try ProtectedFilePolicyV1.applyAndVerify(
                .diagnostics,
                at: countersURL,
                authorityCheck: authorityCheck
            )
            #if DEBUG
            diagnosticBoundary = "replacement-sync-readback"
            #endif
            try syncFile(
                at: countersURL,
                expected: replacementIdentity,
                authorityCheck: authorityCheck
            )
            guard try readData(
                at: countersURL,
                expected: replacementIdentity,
                authorityCheck: authorityCheck
            ) == data,
                  try fileIdentityIfPresent(
                      at: temporaryURL,
                      authorityCheck: authorityCheck
                  ) == nil else {
                throw DiagnosticsFailure.invalidFile
            }
            if oldIdentity != nil,
               let backupIdentity = try fileIdentityIfPresent(
                   at: backupURL,
                   authorityCheck: authorityCheck
               ) {
                if repairExisting {
                    if let staleQuarantine = try fileIdentityIfPresent(
                        at: quarantineURL,
                        authorityCheck: authorityCheck
                    ) {
                        try removeOwnedFile(
                            at: quarantineURL,
                            expected: staleQuarantine,
                            authorityCheck: authorityCheck
                        )
                    }
                    guard try fileIdentityIfPresent(
                        at: backupURL,
                        authorityCheck: authorityCheck
                    ) == backupIdentity else {
                        throw DiagnosticsFailure.invalidFile
                    }
                    try fileManager.moveItem(at: backupURL, to: quarantineURL)
                    try ProtectedFilePolicyV1.applyAndVerify(
                        .diagnostics,
                        at: quarantineURL,
                        authorityCheck: authorityCheck
                    )
                    try ProtectedFilePolicyV1.verify(
                        .diagnostics,
                        at: quarantineURL
                    )
                    let quarantineIdentity = try fileIdentity(
                        at: quarantineURL,
                        authorityCheck: authorityCheck
                    )
                    try syncFile(
                        at: quarantineURL,
                        expected: quarantineIdentity,
                        authorityCheck: authorityCheck
                    )
                } else {
                    try removeOwnedFile(
                        at: backupURL,
                        expected: backupIdentity,
                        authorityCheck: authorityCheck
                    )
                }
                try syncDirectory(authorityCheck: authorityCheck)
            }
            #if DEBUG
            diagnosticBoundary = "directory-sync"
            #endif
            try syncDirectory(authorityCheck: authorityCheck)
            lastCommittedData = data
            return true
        } catch {
            #if DEBUG
            print("Diagnostics persist lastBoundary=\(diagnosticBoundary)")
            #endif
            isPrepared = false
            let cleanupAuthority: () throws -> Void
            if let authority {
                cleanupAuthority = { try authority.verify() }
            } else {
                cleanupAuthority = {}
            }
            if didPublish,
               let replacementIdentity,
               let authority {
                let authorityCheck = { try authority.verify() }
                if oldIdentity != nil,
                   let backupIdentity = try? fileIdentity(
                       at: backupURL,
                       authorityCheck: authorityCheck
                   ),
                   isIdentity(
                       replacementIdentity,
                       at: countersURL,
                       authorityCheck: authorityCheck
                   ) {
                    do {
                        try ProtectedFilePolicyV1.applyAndVerify(
                            .temporaryFile,
                            at: backupURL,
                            authorityCheck: authorityCheck
                        )
                        try authorityCheck()
                        try fileManager.replaceItemAt(
                            countersURL,
                            withItemAt: backupURL,
                            backupItemName: nil,
                            options: []
                        )
                        try ProtectedFilePolicyV1.applyAndVerify(
                            .diagnostics,
                            at: countersURL,
                            authorityCheck: authorityCheck
                        )
                        try syncFile(
                            at: countersURL,
                            expected: backupIdentity,
                            authorityCheck: authorityCheck
                        )
                        try syncDirectory(authorityCheck: authorityCheck)
                    } catch {
                        // Leave the exact replacement for startup recovery.
                    }
                } else if oldIdentity == nil,
                          isIdentity(
                              replacementIdentity,
                              at: countersURL,
                              authorityCheck: authorityCheck
                          ) {
                    try? removeOwnedFile(
                        at: countersURL,
                        expected: replacementIdentity,
                        authorityCheck: authorityCheck
                    )
                    try? syncDirectory(authorityCheck: authorityCheck)
                }
            }
            if let temporaryIdentity,
               isIdentity(
                   temporaryIdentity,
                   at: temporaryURL,
                   authorityCheck: cleanupAuthority
               ) {
                try? removeOwnedFile(
                    at: temporaryURL,
                    expected: temporaryIdentity,
                    authorityCheck: cleanupAuthority
                )
            }
            logger.record(DiagnosticsLogEvent.countersWriteFailed)
            return false
        }
    }

    private func fileIdentityIfPresent(
        at url: URL,
        authorityCheck: () throws -> Void = {}
    ) throws -> FileIdentity? {
        try authorityCheck()
        var information = stat()
        if Darwin.lstat(url.path, &information) == 0 {
            guard (information.st_mode & S_IFMT) == S_IFREG,
                  information.st_nlink == 1 else {
                throw DiagnosticsFailure.invalidFile
            }
            let identity = FileIdentity(information)
            try authorityCheck()
            return identity
        }
        if errno == ENOENT {
            try authorityCheck()
            return nil
        }
        throw DiagnosticsFailure.invalidFile
    }

    private func recoverPendingPublication() throws {
        Self.formatLease.lock()
        defer { Self.formatLease.unlock() }
        guard let authority = try PinnedDiagnosticsAuthority.open(
            applicationSupportURL: applicationSupportURL,
            diagnosticsURL: directoryURL,
            fileManager: fileManager,
            createIfMissing: false
        ) else {
            return
        }
        let authorityCheck = { try authority.verify() }
        let backupURL = directoryURL.appendingPathComponent(
            Self.backupName,
            isDirectory: false
        )
        let temporaryURL = directoryURL.appendingPathComponent(
            Self.temporaryName,
            isDirectory: false
        )
        guard let backupIdentity = try fileIdentityIfPresent(
            at: backupURL,
            authorityCheck: authorityCheck
        ) else {
            guard try fileIdentityIfPresent(
                at: countersURL,
                authorityCheck: authorityCheck
            ) == nil,
                  let temporaryIdentity = try fileIdentityIfPresent(
                    at: temporaryURL,
                    authorityCheck: authorityCheck
                  ),
                  temporaryIdentity.size >= 0,
                  temporaryIdentity.size <= Int64(Self.maximumOperationalTotalBytes) else {
                return
            }
            try ProtectedFilePolicyV1.applyAndVerify(
                .temporaryFile,
                at: temporaryURL,
                authorityCheck: authorityCheck
            )
            let temporaryData = try readData(
                at: temporaryURL,
                expected: temporaryIdentity,
                authorityCheck: authorityCheck
            )
            _ = try decodeOperationalStore(temporaryData)
            try authorityCheck()
            guard try fileIdentityIfPresent(
                at: countersURL,
                authorityCheck: authorityCheck
            ) == nil,
                  try fileIdentityIfPresent(
                    at: temporaryURL,
                    authorityCheck: authorityCheck
                  ) == temporaryIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            try fileManager.moveItem(at: temporaryURL, to: countersURL)
            try authorityCheck()
            guard try fileIdentity(
                at: countersURL,
                authorityCheck: authorityCheck
            ) == temporaryIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            try ProtectedFilePolicyV1.applyAndVerify(
                .diagnostics,
                at: countersURL,
                authorityCheck: authorityCheck
            )
            guard try fileIdentity(
                at: countersURL,
                authorityCheck: authorityCheck
            ) == temporaryIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            try syncFile(
                at: countersURL,
                expected: temporaryIdentity,
                authorityCheck: authorityCheck
            )
            try syncDirectory(authorityCheck: authorityCheck)
            return
        }
        try ProtectedFilePolicyV1.applyAndVerify(
            .temporaryFile,
            at: backupURL,
            authorityCheck: authorityCheck
        )
        try authorityCheck()
        if let currentIdentity = try fileIdentityIfPresent(
            at: countersURL,
            authorityCheck: authorityCheck
        ) {
            do {
                do {
                    try authorityCheck()
                    try ProtectedFilePolicyV1.verify(.diagnostics, at: countersURL)
                    try authorityCheck()
                } catch let failure as ProtectedFilePolicyError
                    where failure == .resourceValueMismatch {
                    let data = try readData(
                        at: countersURL,
                        expected: currentIdentity,
                        authorityCheck: authorityCheck
                    )
                    _ = try decodeOperationalStore(data)
                    try ProtectedFilePolicyV1.applyAndVerify(
                        .diagnostics,
                        at: countersURL,
                        authorityCheck: authorityCheck
                    )
                    try syncFile(
                        at: countersURL,
                        expected: currentIdentity,
                        authorityCheck: authorityCheck
                    )
                }
                let data = try readData(
                    at: countersURL,
                    expected: currentIdentity,
                    authorityCheck: authorityCheck
                )
                _ = try decodeOperationalStore(data)
                try removeOwnedFile(
                    at: backupURL,
                    expected: backupIdentity,
                    authorityCheck: authorityCheck
                )
                try syncDirectory(authorityCheck: authorityCheck)
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                throw failure
            } catch DiagnosticsFailure.unsupportedVersion {
                throw DiagnosticsFailure.unsupportedVersion
            } catch {
                guard currentIdentity != backupIdentity else {
                    throw DiagnosticsFailure.invalidFile
                }
                try ProtectedFilePolicyV1.applyAndVerify(
                    .temporaryFile,
                    at: backupURL,
                    authorityCheck: authorityCheck
                )
                let backupData = try readData(
                    at: backupURL,
                    expected: backupIdentity,
                    authorityCheck: authorityCheck
                )
                _ = try decodeOperationalStore(backupData)
                try authorityCheck()
                try fileManager.replaceItemAt(
                    countersURL,
                    withItemAt: backupURL,
                    backupItemName: nil,
                    options: []
                )
                try ProtectedFilePolicyV1.applyAndVerify(
                    .diagnostics,
                    at: countersURL,
                    authorityCheck: authorityCheck
                )
                try syncFile(
                    at: countersURL,
                    expected: backupIdentity,
                    authorityCheck: authorityCheck
                )
                try syncDirectory(authorityCheck: authorityCheck)
            }
        } else {
            try ProtectedFilePolicyV1.applyAndVerify(
                .temporaryFile,
                at: backupURL,
                authorityCheck: authorityCheck
            )
            let backupData = try readData(
                at: backupURL,
                expected: backupIdentity,
                authorityCheck: authorityCheck
            )
            _ = try decodeOperationalStore(backupData)
            try authorityCheck()
            try fileManager.moveItem(at: backupURL, to: countersURL)
            try ProtectedFilePolicyV1.applyAndVerify(
                .diagnostics,
                at: countersURL,
                authorityCheck: authorityCheck
            )
            try syncFile(
                at: countersURL,
                expected: backupIdentity,
                authorityCheck: authorityCheck
            )
            try syncDirectory(authorityCheck: authorityCheck)
        }
    }

    private func fileIdentity(
        at url: URL,
        authorityCheck: () throws -> Void = {}
    ) throws -> FileIdentity {
        guard let identity = try fileIdentityIfPresent(
            at: url,
            authorityCheck: authorityCheck
        ) else {
            throw DiagnosticsFailure.invalidFile
        }
        return identity
    }

    private func isIdentity(
        _ expected: FileIdentity,
        at url: URL,
        authorityCheck: () throws -> Void = {}
    ) -> Bool {
        guard let actual = try? fileIdentity(
            at: url,
            authorityCheck: authorityCheck
        ) else {
            return false
        }
        return actual == expected
    }

    private func readData(
        at url: URL,
        expected: FileIdentity,
        authorityCheck: () throws -> Void = {}
    ) throws -> Data {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let name = url.lastPathComponent
        guard parent == directoryURL.standardizedFileURL,
              !name.isEmpty else {
            throw DiagnosticsFailure.invalidFile
        }
        try authorityCheck()
        let parentDescriptor = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else {
            throw DiagnosticsFailure.invalidFile
        }
        defer { _ = Darwin.close(parentDescriptor) }
        var parentInformation = stat()
        guard Darwin.fstat(parentDescriptor, &parentInformation) == 0,
              (parentInformation.st_mode & S_IFMT) == S_IFDIR else {
            throw DiagnosticsFailure.invalidFile
        }
        let descriptor = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw DiagnosticsFailure.invalidFile
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              FileIdentity(before) == expected else {
            throw DiagnosticsFailure.invalidFile
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw DiagnosticsFailure.invalidFile
            }
        }
        var after = stat()
        var entry = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              FileIdentity(after) == expected,
              data.count == Int(after.st_size),
              Darwin.fstatat(
                  parentDescriptor,
                  name,
                  &entry,
                  AT_SYMLINK_NOFOLLOW
              ) == 0,
              (entry.st_mode & S_IFMT) == S_IFREG,
              FileIdentity(entry) == expected else {
            throw DiagnosticsFailure.invalidFile
        }
        try authorityCheck()
        return data
    }

    private func syncFile(
        at url: URL,
        expected: FileIdentity,
        authorityCheck: () throws -> Void = {}
    ) throws {
        try authorityCheck()
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw DiagnosticsFailure.invalidFile
        }
        defer { _ = Darwin.close(descriptor) }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              FileIdentity(information) == expected,
              Darwin.fsync(descriptor) == 0 else {
            throw DiagnosticsFailure.invalidFile
        }
        try authorityCheck()
    }

    private func syncDirectory(
        authorityCheck: () throws -> Void = {}
    ) throws {
        try authorityCheck()
        let descriptor = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw DiagnosticsFailure.invalidFile
        }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else {
            throw DiagnosticsFailure.invalidFile
        }
        try authorityCheck()
    }

    private func removeOwnedFile(
        at url: URL,
        expected: FileIdentity,
        authorityCheck: () throws -> Void = {}
    ) throws {
        guard try fileIdentityIfPresent(
            at: url,
            authorityCheck: authorityCheck
        ) == expected else {
            throw DiagnosticsFailure.invalidFile
        }
        try authorityCheck()
        try fileManager.removeItem(at: url)
        try authorityCheck()
        guard try fileIdentityIfPresent(
            at: url,
            authorityCheck: authorityCheck
        ) == nil else {
            throw DiagnosticsFailure.invalidFile
        }
    }

    private func removeFeedbackRecoveryCopyIfPresent() throws {
        guard let authority = try PinnedDiagnosticsAuthority.open(
            applicationSupportURL: applicationSupportURL,
            diagnosticsURL: directoryURL,
            fileManager: fileManager,
            createIfMissing: false
        ) else { return }
        let authorityCheck = { try authority.verify() }
        let quarantineURL = directoryURL.appendingPathComponent(
            Self.quarantineName,
            isDirectory: false
        )
        guard let identity = try fileIdentityIfPresent(
            at: quarantineURL,
            authorityCheck: authorityCheck
        ) else { return }
        _ = try readData(
            at: quarantineURL,
            expected: identity,
            authorityCheck: authorityCheck
        )
        try ProtectedFilePolicyV1.verify(.diagnostics, at: quarantineURL)
        try removeOwnedFile(
            at: quarantineURL,
            expected: identity,
            authorityCheck: authorityCheck
        )
        try syncDirectory(authorityCheck: authorityCheck)
    }

    private func feedbackRecoveryCopyExists() throws -> Bool {
        guard let authority = try PinnedDiagnosticsAuthority.open(
            applicationSupportURL: applicationSupportURL,
            diagnosticsURL: directoryURL,
            fileManager: fileManager,
            createIfMissing: false
        ) else { return false }
        return try fileIdentityIfPresent(
            at: directoryURL.appendingPathComponent(
                Self.quarantineName,
                isDirectory: false
            ),
            authorityCheck: { try authority.verify() }
        ) != nil
    }

    private func canonicalData<T: Encodable>(for value: T) throws -> Data {
        try Self.coldSharedCanonicalData(for: value)
    }

    /// The sole encoder is shared by pure cold planning and the incumbent
    /// actor writer. This helper performs no preparation or filesystem IO.
    fileprivate nonisolated static func coldSharedCanonicalData<T: Encodable>(
        for value: T
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func decodeOperationalStore(
        _ data: Data
    ) throws -> DeviceOperationalSupportEnvelopeV3 {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            if let dictionary = object as? [String: Any],
               let version = dictionary["schemaVersion"] as? NSNumber,
               version.intValue > DeviceOperationalSupportStoreSchemaV3.version {
                throw DiagnosticsFailure.unsupportedVersion
            }
        } catch DiagnosticsFailure.unsupportedVersion {
            throw DiagnosticsFailure.unsupportedVersion
        } catch {
            // Canonical decoding below owns the visible corruption outcome.
        }
        do {
            let value = try JSONDecoder().decode(
                DeviceOperationalSupportEnvelopeV3.self,
                from: data
            )
            try value.validate()
            guard try canonicalData(for: value) == data,
                  data.count <= Self.maximumOperationalTotalBytes else {
                throw DiagnosticsFailure.invalidFile
            }
            return value
        } catch DiagnosticsFailure.invalidFile {
            if schemaVersion(in: data) == DeviceOperationalSupportEnvelopeV3.schemaVersion {
                throw DiagnosticsFailure.recoveryRequired
            }
            // Older released formats are decoded below. Their corrupt bytes
            // retain the existing repair-on-prepare behavior because they
            // could not contain a feedback draft.
        } catch {
            if schemaVersion(in: data) == DeviceOperationalSupportEnvelopeV3.schemaVersion {
                throw DiagnosticsFailure.recoveryRequired
            }
        }
        if let v2 = try? JSONDecoder().decode(DeviceOperationalSupportEnvelopeV2.self, from: data),
           (try? v2.validate()) != nil,
           (try? canonicalData(for: v2)) == data {
            return try DeviceOperationalSupportEnvelopeV3(
                health: v2.health,
                counters: v2.counters,
                feedbackDraft: nil,
                feedbackDraftRecoveryRequired: false
            )
        }
        // A released DiagnosticsV1 document is the sole older format.
        let legacy: DiagnosticsV1
        do {
            legacy = try JSONDecoder().decode(DiagnosticsV1.self, from: data)
            guard legacy.isValid, try canonicalData(for: legacy) == data else {
                throw DiagnosticsFailure.recoveryRequired
            }
        } catch DiagnosticsFailure.recoveryRequired {
            throw DiagnosticsFailure.recoveryRequired
        } catch {
            throw DiagnosticsFailure.recoveryRequired
        }
        let migrated = try DeviceOperationalSupportEnvelopeV3(
            health: try emptyHealth(),
            counters: legacy,
            feedbackDraft: nil,
            feedbackDraftRecoveryRequired: false
        )
        return migrated
    }

    private func isV3Envelope(_ data: Data) -> Bool {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return false
        }
        guard let dictionary = object as? [String: Any],
              let version = dictionary["schemaVersion"] as? NSNumber else {
            return false
        }
        return version.intValue == DeviceOperationalSupportEnvelopeV3.schemaVersion
            && dictionary["health"] != nil
            && dictionary["counters"] != nil
            && dictionary["feedbackDraftRecoveryRequired"] != nil
    }

    private func schemaVersion(in data: Data) -> Int? {
        guard let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = dictionary["schemaVersion"] as? NSNumber else { return nil }
        return version.intValue
    }

    private func canonicalRecordData(_ value: OperationalFailureV1) throws -> Data {
        let data = try canonicalData(for: value)
        try C54EncryptedPortableEnvelopeDiagnosticPrivacyBoundaryV1.validate(data)
        guard data.count <= Self.maximumOperationalRecordBytes else {
            throw DiagnosticsFailure.sizeLimitExceeded
        }
        return data
    }

    private func emptyHealth() throws -> SystemHealthDiagnosticsV1 {
        try Self.makeEmptyHealth(at: now())
    }

    private nonisolated static func makeEmptyHealth(
        at date: Date
    ) throws -> SystemHealthDiagnosticsV1 {
        try SystemHealthDiagnosticsV1(
            generatedAt: date,
            state: .unknown,
            failures: [],
            metricKit: nil
        )
    }

    private func resolvedHealth(
        _ candidate: SystemHealthDiagnosticsV1?
    ) throws -> SystemHealthDiagnosticsV1 {
        if let candidate { return candidate }
        if let health { return health }
        return try emptyHealth()
    }

    private func incremented(_ value: Int64) -> Int64 {
        value == .max ? .max : value + 1
    }

    /// The date comes from the real owner's retained plan or durable recipe.
    /// This method neither samples now nor prepares/repairs the ordinary store.
    func coldCanonicalZeroCandidate(generatedAt: Date) throws -> ColdDiagnosticsCandidateV1 {
        let zeroHealth = try Self.makeEmptyHealth(at: generatedAt)
        let envelope = try DeviceOperationalSupportEnvelopeV3(health: zeroHealth,
            counters: .zero, feedbackDraft: nil, feedbackDraftRecoveryRequired: false)
        let bytes = try Self.coldSharedCanonicalData(for: envelope)
        try Self.requireColdCanonicalZero(bytes, generatedAt: generatedAt)
        return ColdDiagnosticsCandidateV1(store: self,
            applicationSupportURL: applicationSupportURL, diagnosticsURL: directoryURL,
            generatedAt: generatedAt, canonicalBytes: bytes,
            storagePreflight: storagePreflight)
    }

    @MainActor
    static func makeColdCheckedIO(issuer: ColdEraseDiagnosticsEffectIssuerV1,
        candidate: ColdDiagnosticsCandidateV1) throws -> ColdDiagnosticsCheckedIOV1 {
        try issuer.requireHeld()
        guard candidate.diagnosticsIdentity == issuer.diagnosticsIdentity,
              candidate.applicationSupportURL == issuer.applicationSupportURL,
              candidate.diagnosticsURL == issuer.diagnosticsURL,
              candidate.canonicalBytes == issuer.expectedCanonicalBytes else {
            throw DiagnosticsFailure.invalidFile
        }
        try requireColdCanonicalZero(candidate.canonicalBytes,
            generatedAt: candidate.generatedAt)
        let io = ColdDiagnosticsCheckedIOV1(issuer: issuer, candidate: candidate,
            formatLease: formatLease)
        // This actual owner is retained before even a read-only open/pin.
        try issuer.retainCheckedIO(io)
        return io
    }

    func applyColdCacheProjection(_ projection: ColdDiagnosticsCacheProjectionV1) throws {
        guard projection.store === self,
              projection.applicationSupportURL == applicationSupportURL,
              projection.diagnosticsURL == directoryURL else {
            throw DiagnosticsFailure.invalidFile
        }
        let envelope = try Self.requireColdCanonicalZero(projection.canonicalBytes,
            generatedAt: projection.generatedAt)
        counters = envelope.counters
        health = envelope.health
        feedbackDraft = nil
        feedbackDraftRecoveryRequired = false
        lastCommittedData = projection.canonicalBytes
        isPrepared = true
        preparationFailure = nil
    }

    @discardableResult
    fileprivate nonisolated static func requireColdCanonicalZero(_ bytes: Data,
        generatedAt: Date) throws -> DeviceOperationalSupportEnvelopeV3 {
        guard !bytes.isEmpty, bytes.count <= maximumOperationalTotalBytes,
              bytes.count <= 524_288 else { throw DiagnosticsFailure.sizeLimitExceeded }
        let value = try JSONDecoder().decode(DeviceOperationalSupportEnvelopeV3.self, from: bytes)
        try value.validate()
        guard value.counters == .zero, value.health.generatedAt == generatedAt,
              value.health.state == .unknown, value.health.failures.isEmpty,
              value.health.metricKit == nil, value.feedbackDraft == nil,
              !value.feedbackDraftRecoveryRequired else { throw DiagnosticsFailure.invalidFile }
        let canonical = try coldSharedCanonicalData(for: value)
        guard canonical.count <= maximumOperationalTotalBytes,
              canonical.count <= 524_288, canonical == bytes else {
            throw DiagnosticsFailure.invalidFile
        }
        let privacy = try DeviceOperationalSupportEnvelopeV2(health: value.health,
            counters: value.counters)
        try C54EncryptedPortableEnvelopeDiagnosticPrivacyBoundaryV1.validate(
            coldSharedCanonicalData(for: privacy))
        return value
    }
}

// MARK: - Retained cold diagnostics IO in the sole operational-support format

struct ColdDiagnosticsCandidateV1: Sendable {
    fileprivate let store: DiagnosticsStore
    let applicationSupportURL: URL
    let diagnosticsURL: URL
    let generatedAt: Date
    let canonicalBytes: Data
    fileprivate let storagePreflight: StoragePreflightService
    var diagnosticsIdentity: ObjectIdentifier { ObjectIdentifier(store) }
    var sha256: String { KernelCanonicalHashV1.sha256(canonicalBytes) }

    fileprivate init(store: DiagnosticsStore, applicationSupportURL: URL,
        diagnosticsURL: URL, generatedAt: Date, canonicalBytes: Data,
        storagePreflight: StoragePreflightService) {
        self.store = store; self.applicationSupportURL = applicationSupportURL
        self.diagnosticsURL = diagnosticsURL; self.generatedAt = generatedAt
        self.canonicalBytes = canonicalBytes; self.storagePreflight = storagePreflight
    }
}

struct ColdDiagnosticsCacheProjectionV1: Sendable {
    fileprivate let store: DiagnosticsStore
    fileprivate let applicationSupportURL: URL
    fileprivate let diagnosticsURL: URL
    fileprivate let generatedAt: Date
    fileprivate let canonicalBytes: Data
    fileprivate init(candidate: ColdDiagnosticsCandidateV1) {
        store = candidate.store; applicationSupportURL = candidate.applicationSupportURL
        diagnosticsURL = candidate.diagnosticsURL; generatedAt = candidate.generatedAt
        canonicalBytes = candidate.canonicalBytes
    }
}

enum ColdDiagnosticsPrefixV1: Equatable {
    case absentDirectory
    case emptyDirectory
    case temporary(writtenCount: UInt64, policyAccepted: Bool)
    case published
    case completedObservation
}

struct ColdDiagnosticsPhysicalLeafV1: Equatable {
    let name: String
    let fact: EraseColdControlLeafFactV1
    let sha256: String
    let policy: ColdDiagnosticsPolicySnapshotV1
}

struct ColdDiagnosticsPhysicalImageV1: Equatable {
    let supportFact: EraseColdControlLeafFactV1
    let directoryFact: EraseColdControlLeafFactV1?
    let directoryPolicy: ColdDiagnosticsPolicySnapshotV1?
    let directoryNames: [String]
    let leaves: [ColdDiagnosticsPhysicalLeafV1]
}

@MainActor
final class ColdDiagnosticsPrimitiveIntentV1 {
    enum Kind: Equatable {
        case openDirectory, openCurrent, openTemporary, enumerateDirectory
        case observePolicy(kind: OwnedFileKindV1, at: URL)
        case read(resourceID: UUID, offset: UInt64, maximumCount: UInt64)
        case createDirectory, createTemporary
        case write(resourceID: UUID, offset: UInt64, count: UInt64)
        case requestDirectoryPolicy, requestTemporaryPolicy, requestPublishedPolicy
        case syncFile(resourceID: UUID), publishTemporary, syncDirectory, syncSupport
        case closeResource(resourceID: UUID)
    }
    let ioIdentity: ObjectIdentifier
    let operationID: UUID
    let sequence: UInt64
    let kind: Kind
    let before: ColdDiagnosticsPhysicalImageV1?
    fileprivate init(io: ColdDiagnosticsCheckedIOV1, sequence: UInt64, kind: Kind,
        before: ColdDiagnosticsPhysicalImageV1?) {
        ioIdentity = ObjectIdentifier(io); operationID = io.operationID
        self.sequence = sequence; self.kind = kind; self.before = before
    }
}

@MainActor
enum ColdDiagnosticsPrimitiveResultV1 {
    case syscall(returnValue: Int64, savedErrno: Int32)
    case policy(ColdDiagnosticsPolicyEffectScopeV1)
    case enumeration(ColdDiagnosticsEnumerationAttemptV1)
    case policyObservation(ColdDiagnosticsPolicyObservationAttemptV1)
}

@MainActor
final class ColdDiagnosticsPrimitiveOutcomeV1 {
    let intent: ColdDiagnosticsPrimitiveIntentV1
    let result: ColdDiagnosticsPrimitiveResultV1
    fileprivate(set) var after: ColdDiagnosticsPhysicalImageV1?
    fileprivate init(intent: ColdDiagnosticsPrimitiveIntentV1,
        result: ColdDiagnosticsPrimitiveResultV1) {
        self.intent = intent; self.result = result
    }
}

struct ColdDiagnosticsPolicyNodeV1 {
    struct Ancestor {
        let url: URL
        let fullFact: String
        let recordedFullMode: UInt32
        fileprivate init(url: URL, fact: EraseColdControlLeafFactV1) {
            self.url = url; fullFact = ColdDiagnosticsCheckedIOV1.fullFact(fact)
            recordedFullMode = UInt32(fact.mode)
        }
    }
    let kind: OwnedFileKindV1
    let url: URL
    let fullFact: String
    let byteCount: Int64?
    let sha256: String?
    let parentURL: URL
    let parentFullFact: String
    let ancestors: [Ancestor]
    let recordedFullMode: UInt32?
    fileprivate init(kind: OwnedFileKindV1, url: URL,
        fact: EraseColdControlLeafFactV1, byteCount: Int64?, sha256: String?,
        ancestors: [Ancestor]) {
        self.kind = kind; self.url = url; fullFact = ColdDiagnosticsCheckedIOV1.fullFact(fact)
        self.byteCount = byteCount; self.sha256 = sha256; self.ancestors = ancestors
        parentURL = ancestors.last!.url; parentFullFact = ancestors.last!.fullFact
        recordedFullMode = kind == .stagingDirectory ? UInt32(fact.mode) : nil
    }
}

@MainActor
final class ColdDiagnosticsPolicyEffectScopeV1 {
    private enum State { case applying, completed, revoked, uncertain }
    private var state = State.applying
    fileprivate weak var io: ColdDiagnosticsCheckedIOV1?
    private var uncertainIO: ColdDiagnosticsCheckedIOV1?
    fileprivate let primitive: ColdDiagnosticsPrimitiveIntentV1
    let operationID: UUID
    let node: ColdDiagnosticsPolicyNodeV1
    private var attempt: ColdDiagnosticsPolicyAttemptV1?
    private var intents: [ColdDiagnosticsPolicySetterIntentV1] = []
    private var outcomes: [ColdDiagnosticsPolicySetterOutcomeV1] = []
    private var uncertainDescriptors: [Int32] = []
    private var consumedIntent: ColdDiagnosticsPrimitiveIntentV1?

    fileprivate init(io: ColdDiagnosticsCheckedIOV1,
        primitive: ColdDiagnosticsPrimitiveIntentV1, node: ColdDiagnosticsPolicyNodeV1) {
        self.io = io; self.primitive = primitive; self.node = node
        operationID = io.operationID
    }

    func requireCurrentBinding() throws {
        guard state == .applying || state == .completed,
              uncertainDescriptors.isEmpty, let io else { throw DiagnosticsFailure.invalidFile }
        try io.requirePolicyScope(self)
    }

    func requireNode(_ kind: OwnedFileKindV1, at url: URL,
        fullFact: String) throws -> ColdDiagnosticsPolicyNodeV1 {
        try requireCurrentBinding()
        guard kind == node.kind, url == node.url, fullFact == node.fullFact else {
            throw DiagnosticsFailure.invalidFile
        }
        return node
    }

    func retainPolicyAttempt(_ attempt: ColdDiagnosticsPolicyAttemptV1) throws {
        try requireCurrentBinding()
        guard state == .applying, self.attempt == nil,
              attempt.scopeIdentity == ObjectIdentifier(self),
              attempt.operationID == operationID, attempt.kind == node.kind,
              attempt.url == node.url, attempt.beforeFullFact == node.fullFact else {
            throw DiagnosticsFailure.invalidFile
        }
        self.attempt = attempt
    }

    func requirePolicyAttempt(_ attempt: ColdDiagnosticsPolicyAttemptV1) throws {
        try requireCurrentBinding()
        guard self.attempt === attempt, attempt.scopeIdentity == ObjectIdentifier(self),
              attempt.operationID == operationID, attempt.kind == node.kind,
              attempt.url == node.url, attempt.beforeFullFact == node.fullFact else {
            throw DiagnosticsFailure.invalidFile
        }
    }

    func willPerform(_ intent: ColdDiagnosticsPolicySetterIntentV1) throws {
        try requireCurrentBinding()
        guard state == .applying, let attempt, intents.count == outcomes.count,
              intents.count < 2, intent.scopeIdentity == ObjectIdentifier(self),
              intent.operationID == operationID, intent.kind == node.kind,
              intent.url == node.url else { throw DiagnosticsFailure.invalidFile }
        try requirePolicyAttempt(attempt)
        if intents.isEmpty {
            guard intent.step == .completeProtection,
                  intent.beforeFullFact == node.fullFact else { throw DiagnosticsFailure.invalidFile }
        } else {
            guard intent.step == .excludedFromBackup,
                  let after = outcomes[0].afterFullFact,
                  outcomes[0].result == .returned,
                  intent.beforeFullFact == after,
                  ColdDiagnosticsCheckedIOV1.ctimeOnly(after, from: node.fullFact) else {
                throw DiagnosticsFailure.invalidFile
            }
        }
        // Preserve the actual privately created PFP intent before its setter.
        intents.append(intent)
    }

    func didPerform(_ outcome: ColdDiagnosticsPolicySetterOutcomeV1) throws {
        try requireCurrentBinding()
        guard state == .applying, intents.last === outcome.intent,
              outcomes.count + 1 == intents.count,
              outcome.afterFullFact == nil else { throw DiagnosticsFailure.invalidFile }
        // PFP has already captured the true returned/thrown invocation result;
        // its independent postfact has intentionally not been inspected yet.
        outcomes.append(outcome)
        switch outcome.result {
        case .returned:
            guard outcome.actualError == nil else { poisonOnUncertainEffect(); throw DiagnosticsFailure.invalidFile }
        case .threw:
            poisonOnUncertainEffect()
            guard let error = outcome.actualError else { throw DiagnosticsFailure.invalidFile }
            throw error
        }
    }

    func completePolicyAttempt(_ attempt: ColdDiagnosticsPolicyAttemptV1) throws {
        try requirePolicyAttempt(attempt)
        try attempt.requireCheckedSettlement()
        guard state == .applying, intents.count == 2, outcomes.count == 2,
              outcomes[0].intent === intents[0], outcomes[1].intent === intents[1],
              outcomes.allSatisfy({ $0.result == .returned && $0.actualError == nil }),
              let first = outcomes[0].afterFullFact,
              let final = outcomes[1].afterFullFact,
              first == intents[1].beforeFullFact, final == attempt.finalFullFact,
              ColdDiagnosticsCheckedIOV1.ctimeOnly(first, from: node.fullFact),
              ColdDiagnosticsCheckedIOV1.ctimeOnly(final, from: first),
              let value = attempt.value,
              value.backupExcluded == true,
              value.isDirectory == (node.kind == .stagingDirectory) else {
            throw DiagnosticsFailure.invalidFile
        }
        state = .completed
    }

    func retainUncertainDescriptor(_ descriptor: Int32) {
        if !uncertainDescriptors.contains(descriptor) { uncertainDescriptors.append(descriptor) }
        if let io {
            uncertainIO = io
            io.retainUncertainPolicyDescriptor(descriptor)
        }
        state = .uncertain
    }

    func poisonOnUncertainEffect() {
        state = .uncertain
        if let io { uncertainIO = io; io.poison() }
    }

    fileprivate func requireCompleted() throws {
        guard state == .completed, uncertainDescriptors.isEmpty, let attempt else {
            throw DiagnosticsFailure.invalidFile
        }
        try attempt.requireCheckedSettlement()
        guard attempt.finalFullFact == outcomes.last?.afterFullFact,
              attempt.value != nil else { throw DiagnosticsFailure.invalidFile }
    }

    fileprivate var finalFullFact: String? { attempt?.finalFullFact }
    fileprivate var value: TemporalPolicyObservationV1? { attempt?.value }

    fileprivate func revokeAfterConsumption() throws {
        try requireCompleted()
        guard let io, let attempt else { throw DiagnosticsFailure.invalidFile }
        try io.requireConsumedPolicyScope(self)
        // No actual setter/resource owner is released before its outer result
        // and full projection have been consumed by the real issuer.
        consumedIntent = primitive; state = .revoked
        do { try attempt.releaseConsumedScope(self) }
        catch { poisonOnUncertainEffect(); throw error }
    }

    func requireConsumedPolicyAttempt(_ attempt: ColdDiagnosticsPolicyAttemptV1) throws {
        guard state == .revoked, self.attempt === attempt, consumedIntent === primitive,
              attempt.scopeIdentity == ObjectIdentifier(self), attempt.operationID == operationID,
              uncertainDescriptors.isEmpty, uncertainIO == nil else { throw DiagnosticsFailure.invalidFile }
        try attempt.requireCheckedSettlement()
    }

    fileprivate func requireRevokedSettlement() throws {
        guard state == .revoked, uncertainDescriptors.isEmpty, let attempt else {
            throw DiagnosticsFailure.invalidFile
        }
        try attempt.requireCheckedSettlement()
    }
}

/// Read-only raw policy DATA. This scope has no setter entry and cannot mint
/// accepted protection from an unrequested or decoded observation.
@MainActor
final class ColdDiagnosticsPolicyObservationScopeV1 {
    private enum State { case observing, completed, revoked, uncertain }
    private var state = State.observing
    fileprivate weak var io: ColdDiagnosticsCheckedIOV1?
    private var uncertainIO: ColdDiagnosticsCheckedIOV1?
    fileprivate let primitive: ColdDiagnosticsPrimitiveIntentV1
    let operationID: UUID
    let node: ColdDiagnosticsPolicyNodeV1
    private var attempt: ColdDiagnosticsPolicyObservationAttemptV1?
    private var consumedIntent: ColdDiagnosticsPrimitiveIntentV1?
    private var uncertainDescriptors: [Int32] = []

    fileprivate init(io: ColdDiagnosticsCheckedIOV1,
        primitive: ColdDiagnosticsPrimitiveIntentV1, node: ColdDiagnosticsPolicyNodeV1) {
        self.io = io; self.primitive = primitive; self.node = node
        operationID = io.operationID
    }

    func requireCurrentBinding() throws {
        guard state == .observing || state == .completed,
              uncertainDescriptors.isEmpty, let io else { throw DiagnosticsFailure.invalidFile }
        try io.requirePolicyObservationScope(self)
    }

    func requireNode(_ kind: OwnedFileKindV1, at url: URL,
        fullFact: String) throws -> ColdDiagnosticsPolicyNodeV1 {
        try requireCurrentBinding()
        guard node.kind == kind, node.url == url, node.fullFact == fullFact else {
            throw DiagnosticsFailure.invalidFile
        }
        return node
    }

    func retainObservationAttempt(_ attempt: ColdDiagnosticsPolicyObservationAttemptV1) throws {
        try requireCurrentBinding()
        guard state == .observing, self.attempt == nil,
              attempt.scopeIdentity == ObjectIdentifier(self), attempt.operationID == operationID,
              attempt.kind == node.kind, attempt.url == node.url,
              attempt.beforeFullFact == node.fullFact else { throw DiagnosticsFailure.invalidFile }
        self.attempt = attempt
    }

    func requireObservationAttempt(_ attempt: ColdDiagnosticsPolicyObservationAttemptV1) throws {
        try requireCurrentBinding()
        guard self.attempt === attempt, attempt.scopeIdentity == ObjectIdentifier(self),
              attempt.operationID == operationID, attempt.kind == node.kind,
              attempt.url == node.url, attempt.beforeFullFact == node.fullFact else {
            throw DiagnosticsFailure.invalidFile
        }
    }

    func completeObservationAttempt(_ attempt: ColdDiagnosticsPolicyObservationAttemptV1) throws {
        try requireObservationAttempt(attempt)
        try attempt.requireCheckedSettlement()
        guard state == .observing, let value = attempt.value,
              ColdDiagnosticsCheckedIOV1.snapshot(value, matches: node.fullFact),
              value.isDirectory == (node.kind == .stagingDirectory) else {
            throw DiagnosticsFailure.invalidFile
        }
        state = .completed
    }

    func retainUncertainDescriptor(_ descriptor: Int32) {
        if !uncertainDescriptors.contains(descriptor) { uncertainDescriptors.append(descriptor) }
        poisonOnUncertainObservation()
    }

    func poisonOnUncertainObservation() {
        if let io { uncertainIO = io; io.retainUncertainRawPolicyScope(self) }
        state = .uncertain
    }

    fileprivate func requireCompleted() throws {
        guard state == .completed, uncertainDescriptors.isEmpty, let attempt,
              let value = attempt.value,
              ColdDiagnosticsCheckedIOV1.snapshot(value, matches: node.fullFact) else {
            throw DiagnosticsFailure.invalidFile
        }
        try attempt.requireCheckedSettlement()
    }

    fileprivate var actualAttempt: ColdDiagnosticsPolicyObservationAttemptV1? { attempt }
    fileprivate var value: ColdDiagnosticsPolicySnapshotV1? { attempt?.value }

    fileprivate func revokeAfterConsumption() throws {
        try requireCompleted()
        guard let io, let attempt else { throw DiagnosticsFailure.invalidFile }
        try io.requireConsumedPolicyObservationScope(self)
        consumedIntent = primitive; state = .revoked
        do { try attempt.releaseConsumedScope(self) }
        catch { poisonOnUncertainObservation(); throw error }
    }

    func requireConsumedObservationAttempt(_ attempt: ColdDiagnosticsPolicyObservationAttemptV1) throws {
        guard state == .revoked, self.attempt === attempt, consumedIntent === primitive,
              attempt.scopeIdentity == ObjectIdentifier(self), attempt.operationID == operationID,
              uncertainDescriptors.isEmpty, uncertainIO == nil else { throw DiagnosticsFailure.invalidFile }
        try attempt.requireCheckedSettlement()
    }

    fileprivate func requireRevokedSettlement() throws {
        guard state == .revoked, uncertainDescriptors.isEmpty, let attempt else {
            throw DiagnosticsFailure.invalidFile
        }
        try attempt.requireCheckedSettlement()
    }
}

@MainActor
fileprivate final class ColdDiagnosticsResourceV1 {
    enum Role { case directory, current, temporary, observer, enumeration }
    enum State { case unopened, open, directoryStream, closeEntered, closed, uncertain }
    let id = UUID()
    let role: Role
    var state = State.unopened
    var descriptor: Int32?
    var openedDescriptor: Int32?
    var directoryStream: UnsafeMutablePointer<DIR>?
    var fencedDirectoryStream: UnsafeMutablePointer<DIR>?
    var fact: EraseColdControlLeafFactV1?
    var closeResult: Int32?
    var closeErrno: Int32?
    var closedByIntent: ColdDiagnosticsPrimitiveIntentV1?
    init(role: Role) { self.role = role }
    // Intentionally no deinit close. The actual issuer retains uncertainty.
}

@MainActor
final class ColdDiagnosticsEnumerationAttemptV1 {
    enum ReadResult { case entry(address: UInt, savedErrno: Int32), eof(savedErrno: Int32) }
    fileprivate enum State { case entered, streamOwned, closed, uncertain }
    fileprivate var state = State.entered
    fileprivate let resource: ColdDiagnosticsResourceV1
    let ioIdentity: ObjectIdentifier
    let operationID: UUID
    fileprivate(set) var names: [String] = []
    fileprivate(set) var reachedEOF = false
    fileprivate(set) var fdopendirErrno: Int32?
    fileprivate(set) var fdopendirReturn: UInt?
    fileprivate(set) var readdirErrnos: [Int32] = []
    fileprivate(set) var actualReads: [ReadResult] = []
    fileprivate(set) var closeResult: Int32?
    fileprivate(set) var closeErrno: Int32?
    fileprivate init(io: ColdDiagnosticsCheckedIOV1, resource: ColdDiagnosticsResourceV1) {
        ioIdentity = ObjectIdentifier(io); operationID = io.operationID
        self.resource = resource
    }
    fileprivate func requireCheckedSettlement() throws {
        guard state == .closed, reachedEOF, fdopendirErrno != nil, fdopendirReturn != nil,
              actualReads.count == readdirErrnos.count,
              readdirErrnos.last == 0, closeResult == 0, closeErrno != nil,
              resource.state == .closed, resource.descriptor == nil,
              resource.directoryStream == nil,
              names == names.sorted(), Set(names).count == names.count,
              names.count <= 2,
              names.allSatisfy({ $0 == "counters.json" || $0 == ".counters.json.next" }) else {
            throw DiagnosticsFailure.invalidFile
        }
    }
}

@MainActor
final class ColdDiagnosticsCheckedReceiptV1 {
    let ioIdentity: ObjectIdentifier
    let operationID: UUID
    let canonicalSHA256: String
    let byteCount: UInt64
    let currentImage: ColdDiagnosticsPhysicalImageV1
    let closedResourceIDs: [UUID]
    let closedResourceCount: UInt64
    let closedResourceCensusSHA256: String
    let closedPolicyObservationCount: UInt64
    let closedPolicyObservationResourceCount: UInt64
    let closedPolicyObservationCensusSHA256: String
    fileprivate init(io: ColdDiagnosticsCheckedIOV1, image: ColdDiagnosticsPhysicalImageV1,
        closedResourceIDs: [UUID], closedResourceCount: UInt64, censusSHA256: String,
        policyObservationCount: UInt64, policyObservationResourceCount: UInt64,
        policyObservationCensusSHA256: String) {
        ioIdentity = ObjectIdentifier(io); operationID = io.operationID
        canonicalSHA256 = io.candidate.sha256
        byteCount = UInt64(io.candidate.canonicalBytes.count); currentImage = image
        self.closedResourceIDs = closedResourceIDs; self.closedResourceCount = closedResourceCount
        closedResourceCensusSHA256 = censusSHA256
        closedPolicyObservationCount = policyObservationCount
        closedPolicyObservationResourceCount = policyObservationResourceCount
        closedPolicyObservationCensusSHA256 = policyObservationCensusSHA256
    }
}

/// A real current-process policy prerequisite, never a decoded historical
/// request. The main terminal owner must retain this exact object and IO.
@MainActor
final class ColdDiagnosticsCompletedPolicyReceiptV1 {
    private weak var actualIssuer: ColdEraseDiagnosticsEffectIssuerV1?
    let actualPrerequisiteIO: ColdDiagnosticsCheckedIOV1
    let checkedReceipt: ColdDiagnosticsCheckedReceiptV1
    let issuerIdentity: ObjectIdentifier
    let operationID: UUID
    let diagnosticsIdentity: ObjectIdentifier
    let canonicalIntent: EraseIntentV1
    let canonicalIntentSHA256: String
    let candidateSHA256: String
    let byteCount: UInt64
    let currentImage: ColdDiagnosticsPhysicalImageV1
    let closedResourceCount: UInt64
    let closedResourceCensusSHA256: String

    fileprivate init(io: ColdDiagnosticsCheckedIOV1,
        issuer: ColdEraseDiagnosticsEffectIssuerV1,
        receipt: ColdDiagnosticsCheckedReceiptV1) {
        actualIssuer = issuer; actualPrerequisiteIO = io; checkedReceipt = receipt
        issuerIdentity = ObjectIdentifier(issuer); operationID = io.operationID
        diagnosticsIdentity = io.diagnosticsIdentity
        canonicalIntent = issuer.canonicalIntent
        canonicalIntentSHA256 = issuer.canonicalIntentSHA256
        candidateSHA256 = receipt.canonicalSHA256; byteCount = receipt.byteCount
        currentImage = receipt.currentImage
        closedResourceCount = receipt.closedResourceCount
        closedResourceCensusSHA256 = receipt.closedResourceCensusSHA256
    }

    /// Memory-only association proof. Physical observation/EX/C/K admission
    /// is rejoined by the actual main owner; this DATA does not issue effects.
    func requireCurrentProcessBinding(issuer: ColdEraseDiagnosticsEffectIssuerV1,
        actualImage: ColdDiagnosticsPhysicalImageV1) throws {
        guard actualIssuer === issuer, ObjectIdentifier(issuer) == issuerIdentity,
              issuer.operationID == operationID,
              issuer.diagnosticsIdentity == diagnosticsIdentity,
              issuer.canonicalIntent == canonicalIntent,
              issuer.canonicalIntentSHA256 == canonicalIntentSHA256,
              actualPrerequisiteIO.mode == .requestCompletedZeroPolicy,
              actualPrerequisiteIO.issuerIdentity == issuerIdentity,
              actualPrerequisiteIO.operationID == operationID,
              actualPrerequisiteIO.diagnosticsIdentity == diagnosticsIdentity,
              checkedReceipt.currentImage == currentImage, actualImage == currentImage,
              checkedReceipt.canonicalSHA256 == candidateSHA256,
              checkedReceipt.byteCount == byteCount,
              checkedReceipt.closedResourceCount == closedResourceCount,
              checkedReceipt.closedResourceCensusSHA256 == closedResourceCensusSHA256 else {
            throw DiagnosticsFailure.invalidFile
        }
        try actualPrerequisiteIO.requireLiveCompletedPolicyBinding(issuer: issuer)
        try actualPrerequisiteIO.requireIssuerCheckedSettlement(receipt: checkedReceipt)
        try actualPrerequisiteIO.requireCompletedPolicySequence()
    }
}

#if DEBUG
/// Projects the retained primitive description without exposing its URL,
/// resource identity or other associated values. This is diagnostic DATA
/// only; it neither replaces the retained boundary nor authorizes an effect.
enum ColdDiagnosticsBoundaryLabelV1 {
    static func project(_ boundary: String) -> String {
        switch boundary {
        case "registered": return "registered"
        case "openDirectory": return "openDirectory"
        case "openCurrent": return "openCurrent"
        case "openTemporary": return "openTemporary"
        case "enumerateDirectory": return "enumerateDirectory"
        case "createDirectory": return "createDirectory"
        case "createTemporary": return "createTemporary"
        case "requestDirectoryPolicy": return "requestDirectoryPolicy"
        case "requestTemporaryPolicy": return "requestTemporaryPolicy"
        case "requestPublishedPolicy": return "requestPublishedPolicy"
        case "publishTemporary": return "publishTemporary"
        case "syncDirectory": return "syncDirectory"
        case "syncSupport": return "syncSupport"
        case let value where value.hasPrefix("observePolicy(") && value.hasSuffix(")"):
            return "observePolicy"
        case let value where value.hasPrefix("read(") && value.hasSuffix(")"):
            return "read"
        case let value where value.hasPrefix("write(") && value.hasSuffix(")"):
            return "write"
        case let value where value.hasPrefix("syncFile(") && value.hasSuffix(")"):
            return "syncFile"
        case let value where value.hasPrefix("closeResource(") && value.hasSuffix(")"):
            return "closeResource"
        default: return "unclassified"
        }
    }
}
#endif

@MainActor
final class ColdDiagnosticsCheckedIOV1 {
    enum Mode: Equatable {
        case replaceWithCanonicalZero, observeCompletedZero, requestCompletedZeroPolicy
    }
    private enum State { case registered, performing, checkedClosed, uncertain }
    private final class Frame {
        let intent: ColdDiagnosticsPrimitiveIntentV1
        let mutation: Bool
        var outcome: ColdDiagnosticsPrimitiveOutcomeV1?
        var proved = false
        init(intent: ColdDiagnosticsPrimitiveIntentV1, mutation: Bool) {
            self.intent = intent; self.mutation = mutation
        }
    }
    fileprivate let candidate: ColdDiagnosticsCandidateV1
    private weak var issuer: ColdEraseDiagnosticsEffectIssuerV1?
    // Set before the first delegated operation. Every uncertain path keeps
    // the actual owner strongly; only genuine final consumption releases it.
    private var retainedIssuer: ColdEraseDiagnosticsEffectIssuerV1?
    private var issuerReleased = false
    private let formatLease: NSRecursiveLock
    let issuerIdentity: ObjectIdentifier
    let diagnosticsIdentity: ObjectIdentifier
    let operationID: UUID
    let mode: Mode
    private var state = State.registered
    private var frameEntered = false
    private var sequence: UInt64 = 0
    private var lastBoundary = "registered"
    private var stack: [Frame] = []
    private var lastConsumedOutcome: ColdDiagnosticsPrimitiveOutcomeV1?
    private var resources: [ColdDiagnosticsResourceV1] = []
    private var retiringResources: [ColdDiagnosticsResourceV1] = []
    private var retiringEnumerations: [ColdDiagnosticsEnumerationAttemptV1] = []
    private var directory: ColdDiagnosticsResourceV1?
    private var temporary: ColdDiagnosticsResourceV1?
    private var current: ColdDiagnosticsResourceV1?
    private var observer: ColdDiagnosticsResourceV1?
    private var enumeration: ColdDiagnosticsEnumerationAttemptV1?
    private var policyScope: ColdDiagnosticsPolicyEffectScopeV1?
    private var policyScopes: [ColdDiagnosticsPolicyEffectScopeV1] = []
    private var policyObservationScope: ColdDiagnosticsPolicyObservationScopeV1?
    private var retiringPolicyObservations: [ColdDiagnosticsPolicyObservationScopeV1] = []
    private var uncertainPolicyObservationScope: ColdDiagnosticsPolicyObservationScopeV1?
    private var uncertainPolicyDescriptors: [Int32] = []
    private var acceptedDirectoryPolicy: TemporalPolicyObservationV1?
    private var acceptedLeafPolicy: TemporalPolicyObservationV1?
    private var receipt: ColdDiagnosticsCheckedReceiptV1?
    private weak var completedPolicyReceiptValue: ColdDiagnosticsCompletedPolicyReceiptV1?
    private var completedPolicyReceiptMinted = false
    private var closedResourceCount: UInt64 = 0
    private var closedResourceCensus = SHA256()
    private var finalClosedResourceCensusSHA256: String?
    private var closedPolicyObservationCount: UInt64 = 0
    private var closedPolicyObservationResourceCount: UInt64 = 0
    private var closedPolicyObservationCensus = SHA256()
    private var finalPolicyObservationCensusSHA256: String?
    private(set) var currentImage: ColdDiagnosticsPhysicalImageV1?
    private static let directoryName = "FieldEvidenceDiagnostics"
    private static let currentName = "counters.json"
    private static let temporaryName = ".counters.json.next"

    fileprivate init(issuer: ColdEraseDiagnosticsEffectIssuerV1,
        candidate: ColdDiagnosticsCandidateV1, formatLease: NSRecursiveLock) {
        self.issuer = issuer; self.candidate = candidate; self.formatLease = formatLease
        issuerIdentity = ObjectIdentifier(issuer); diagnosticsIdentity = candidate.diagnosticsIdentity
        operationID = issuer.operationID; mode = issuer.mode
    }

    fileprivate func poison() {
        if let issuer { retainedIssuer = issuer }
        state = .uncertain
        retainedIssuer?.poisonOnUncertainIO()
    }

    private func requireIssuerAssociation() throws -> ColdEraseDiagnosticsEffectIssuerV1 {
        guard !issuerReleased, let issuer,
              ObjectIdentifier(issuer) == issuerIdentity,
              issuer.operationID == operationID,
              issuer.diagnosticsIdentity == diagnosticsIdentity else {
            throw DiagnosticsFailure.invalidFile
        }
        return issuer
    }

    fileprivate func retainUncertainPolicyDescriptor(_ descriptor: Int32) {
        if !uncertainPolicyDescriptors.contains(descriptor) {
            uncertainPolicyDescriptors.append(descriptor)
        }
        poison()
    }

    fileprivate func retainUncertainRawPolicyScope(_ scope: ColdDiagnosticsPolicyObservationScopeV1) {
        if uncertainPolicyObservationScope == nil { uncertainPolicyObservationScope = scope }
        poison()
    }

    private func requireCurrent() throws {
        let issuer = try requireIssuerAssociation()
        guard state == .performing, frameEntered, uncertainPolicyDescriptors.isEmpty else {
            throw DiagnosticsFailure.invalidFile
        }
        try issuer.requireHeld()
        try issuer.requireCheckedIO(self)
        if let frame = stack.last {
            try issuer.requirePrimitive(frame.intent, outcome: frame.outcome, io: self)
        }
    }

    func requireIssuerPrimitive(intent: ColdDiagnosticsPrimitiveIntentV1,
        outcome: ColdDiagnosticsPrimitiveOutcomeV1?) throws {
        guard state == .performing, frameEntered, uncertainPolicyDescriptors.isEmpty,
              intent.ioIdentity == ObjectIdentifier(self), intent.operationID == operationID,
              let frame = stack.first(where: { $0.intent === intent }) else {
            throw DiagnosticsFailure.invalidFile
        }
        if let outcome {
            guard frame.outcome === outcome, outcome.intent === intent else {
                throw DiagnosticsFailure.invalidFile
            }
            switch outcome.result {
            case .syscall: break
            case .policy(let scope):
                guard policyScope === scope, scope.io === self, scope.primitive === intent else {
                    throw DiagnosticsFailure.invalidFile
                }
                try scope.requireCompleted()
            case .enumeration(let attempt):
                guard enumeration === attempt, attempt.ioIdentity == ObjectIdentifier(self),
                      attempt.operationID == operationID else { throw DiagnosticsFailure.invalidFile }
                try attempt.requireCheckedSettlement()
            case .policyObservation(let attempt):
                guard let scope = policyObservationScope, scope.io === self,
                      scope.primitive === intent, scope.actualAttempt === attempt,
                      attempt.scopeIdentity == ObjectIdentifier(scope),
                      attempt.operationID == operationID else { throw DiagnosticsFailure.invalidFile }
                try scope.requireCompleted()
            }
        } else {
            guard frame.outcome == nil else { throw DiagnosticsFailure.invalidFile }
        }
    }

    func requireIssuerCompletedPrimitive(_ outcome: ColdDiagnosticsPrimitiveOutcomeV1) throws {
        try requireIssuerPrimitive(intent: outcome.intent, outcome: outcome)
        guard let frame = stack.last, frame.intent === outcome.intent,
              frame.outcome === outcome, frame.proved,
              !frame.mutation || (outcome.after != nil && outcome.after == currentImage) else {
            throw DiagnosticsFailure.invalidFile
        }
    }

    fileprivate func requirePolicyScope(_ scope: ColdDiagnosticsPolicyEffectScopeV1) throws {
        let issuer = try requireIssuerAssociation()
        guard policyScope === scope, scope.io === self, frameEntered,
              state == .performing, stack.contains(where: { $0.intent === scope.primitive }) else {
            throw DiagnosticsFailure.invalidFile
        }
        try issuer.requireHeld()
        try issuer.requirePrimitive(scope.primitive,
            outcome: stack.first(where: { $0.intent === scope.primitive })?.outcome, io: self)
    }

    fileprivate func requireConsumedPolicyScope(_ scope: ColdDiagnosticsPolicyEffectScopeV1) throws {
        guard state == .performing, policyScope === scope, scope.io === self,
              let actual = lastConsumedOutcome, actual.intent === scope.primitive,
              actual.after == currentImage, stack.isEmpty,
              case .policy(let bound) = actual.result, bound === scope else {
            throw DiagnosticsFailure.invalidFile
        }
        try scope.requireCompleted()
    }

    fileprivate func requirePolicyObservationScope(_ scope: ColdDiagnosticsPolicyObservationScopeV1) throws {
        let issuer = try requireIssuerAssociation()
        guard policyObservationScope === scope, scope.io === self,
              frameEntered, state == .performing,
              scope.primitive.kind == .observePolicy(kind: scope.node.kind, at: scope.node.url),
              let frame = stack.first(where: { $0.intent === scope.primitive }) else {
            throw DiagnosticsFailure.invalidFile
        }
        try issuer.requireHeld()
        try issuer.requirePrimitive(scope.primitive, outcome: frame.outcome, io: self)
    }

    fileprivate func requireConsumedPolicyObservationScope(_ scope: ColdDiagnosticsPolicyObservationScopeV1) throws {
        guard state == .performing, policyObservationScope === scope, scope.io === self,
              let actual = lastConsumedOutcome, actual.intent === scope.primitive,
              case .policyObservation(let attempt) = actual.result,
              scope.actualAttempt === attempt,
              stack.allSatisfy({ $0.outcome != nil }) else { throw DiagnosticsFailure.invalidFile }
        try scope.requireCompleted()
    }

    private func begin(_ kind: ColdDiagnosticsPrimitiveIntentV1.Kind,
        mutation: Bool = false) throws -> Frame {
        let issuer = try requireIssuerAssociation()
        try requireCurrent()
        if mutation {
            switch mode {
            case .observeCompletedZero:
                throw DiagnosticsFailure.invalidFile
            case .requestCompletedZeroPolicy:
                guard kind == .requestDirectoryPolicy || kind == .requestPublishedPolicy else {
                    throw DiagnosticsFailure.invalidFile
                }
            case .replaceWithCanonicalZero: break
            }
        }
        guard stack.count < 3,
              stack.last == nil || (!mutation && stack.last?.outcome != nil),
              !mutation || currentImage != nil else { throw DiagnosticsFailure.invalidFile }
        // Positive short writes/reads consume at least one recipe byte. Full
        // before/after scans can each require one read per byte, so the finite
        // call ceiling must include that quadratic worst case. It allocates
        // no history: at most three actual frames/five resources are retained.
        let bytes = UInt64(candidate.canonicalBytes.count)
        guard bytes <= 524_288 else { throw DiagnosticsFailure.sizeLimitExceeded }
        let maximum = (bytes + 1) * (4 * bytes + 256) + 8_192
        guard sequence < maximum else { throw DiagnosticsFailure.sizeLimitExceeded }
        sequence += 1
        lastBoundary = String(describing: kind)
        let intent = ColdDiagnosticsPrimitiveIntentV1(io: self, sequence: sequence,
            kind: kind, before: currentImage)
        let frame = Frame(intent: intent, mutation: mutation)
        stack.append(frame)
        try issuer.willPerform(intent, io: self)
        return frame
    }

    private func capture(_ result: ColdDiagnosticsPrimitiveResultV1,
        frame: Frame) throws -> ColdDiagnosticsPrimitiveOutcomeV1 {
        let issuer = try requireIssuerAssociation()
        guard stack.last === frame, frame.outcome == nil else { throw DiagnosticsFailure.invalidFile }
        let outcome = ColdDiagnosticsPrimitiveOutcomeV1(intent: frame.intent, result: result)
        frame.outcome = outcome // Retain the real result before callbacks/proof.
        try issuer.didPerform(outcome, io: self)
        return outcome
    }

    private func complete(_ frame: Frame,
        after: ColdDiagnosticsPhysicalImageV1? = nil) throws {
        let issuer = try requireIssuerAssociation()
        guard stack.last === frame, let outcome = frame.outcome, !frame.proved else {
            throw DiagnosticsFailure.invalidFile
        }
        outcome.after = after
        if let after { currentImage = after }
        frame.proved = true
        try issuer.completePrimitive(outcome, io: self)
        // Only the genuine issuer's consumption permits retiring a successful
        // transient frame. An uncertain stack is never compacted.
        guard stack.last === frame, state == .performing else { throw DiagnosticsFailure.invalidFile }
        stack.removeLast()
        lastConsumedOutcome = outcome
        if after != nil { try retireObservedResources() }
    }

    private func syscall(_ kind: ColdDiagnosticsPrimitiveIntentV1.Kind,
        mutation: Bool = false, body: () -> Int64,
        retain: (Int64, Int32) -> Void = { _, _ in },
        proof: (Int64, Int32) throws -> ColdDiagnosticsPhysicalImageV1? = { _, _ in nil }
    ) throws -> Int64 {
        let frame = try begin(kind, mutation: mutation)
        let result = body()
        let savedErrno = errno
        retain(result, savedErrno)
        _ = try capture(.syscall(returnValue: result, savedErrno: savedErrno), frame: frame)
        let after = try proof(result, savedErrno)
        try complete(frame, after: after)
        return result
    }

    private func makeResource(_ role: ColdDiagnosticsResourceV1.Role) throws -> ColdDiagnosticsResourceV1 {
        guard resources.count < 5 else { throw DiagnosticsFailure.sizeLimitExceeded }
        let resource = ColdDiagnosticsResourceV1(role: role)
        resources.append(resource) // Genuine owner exists before the open.
        return resource
    }

    private func descriptor(_ resource: ColdDiagnosticsResourceV1) throws -> Int32 {
        guard resource.state == .open, let descriptor = resource.descriptor else {
            throw DiagnosticsFailure.invalidFile
        }
        return descriptor
    }

    private func directoryDescriptor() throws -> Int32 {
        guard let directory else { throw DiagnosticsFailure.invalidFile }
        return try descriptor(directory)
    }

    private func rememberClose(_ resource: ColdDiagnosticsResourceV1,
        retire: Bool) throws {
        guard resource.state == .closed, resource.closeResult == 0,
              let saved = resource.closeErrno, let actualIntent = resource.closedByIntent,
              actualIntent.operationID == operationID,
              actualIntent.ioIdentity == ObjectIdentifier(self), resource.descriptor == nil,
              resource.directoryStream == nil, closedResourceCount < UInt64.max else {
            throw DiagnosticsFailure.invalidFile
        }
        closedResourceCount += 1
        closedResourceCensus.update(data: Data(
            "\(resource.id.uuidString.lowercased())|0|\(saved)|\(actualIntent.operationID.uuidString.lowercased())|\(actualIntent.sequence)\n".utf8))
        if retire {
            guard resources.contains(where: { $0 === resource }), state == .performing else {
                throw DiagnosticsFailure.invalidFile
            }
            resources.removeAll { $0 === resource }
        }
    }

    private func close(_ resource: ColdDiagnosticsResourceV1,
        retire: Bool = false) throws {
        let fd = try descriptor(resource)
        let frame = try begin(.closeResource(resourceID: resource.id))
        resource.closedByIntent = frame.intent
        // Detach before entering close. No failure path retries this FD.
        resource.descriptor = nil; resource.state = .closeEntered
        let result = Darwin.close(fd)
        let saved = errno
        resource.closeResult = result; resource.closeErrno = saved
        resource.state = result == 0 ? .closed : .uncertain
        _ = try capture(.syscall(returnValue: Int64(result), savedErrno: saved), frame: frame)
        guard result == 0 else { throw DiagnosticsFailure.invalidFile }
        try complete(frame)
        if retire {
            guard retiringResources.count < 3 else { throw DiagnosticsFailure.sizeLimitExceeded }
            retiringResources.append(resource)
        } else { try rememberClose(resource, retire: false) }
    }

    private func retireObservedResources() throws {
        // Whole-image consumers have finished and the real issuer consumed
        // their parent result (or rejoined the unchanged image). Only now can
        // positively closed transient owners leave the retained census.
        guard state == .performing, observer == nil, enumeration == nil,
              policyObservationScope == nil, uncertainPolicyObservationScope == nil else {
            throw DiagnosticsFailure.invalidFile
        }
        for attempt in retiringEnumerations { try attempt.requireCheckedSettlement() }
        for resource in retiringResources { try rememberClose(resource, retire: true) }
        retiringResources.removeAll(); retiringEnumerations.removeAll()
        for scope in retiringPolicyObservations {
            try scope.requireRevokedSettlement()
            guard let attempt = scope.actualAttempt,
                  closedPolicyObservationCount < UInt64.max else { throw DiagnosticsFailure.invalidFile }
            let sum = closedPolicyObservationResourceCount.addingReportingOverflow(attempt.closedResourceCount)
            guard !sum.overflow, attempt.closedResourceCount > 0,
                  attempt.closedResourceCount <= 3,
                  attempt.closedResourceCensusSHA256.count == 64 else { throw DiagnosticsFailure.invalidFile }
            closedPolicyObservationCount += 1; closedPolicyObservationResourceCount = sum.partialValue
            closedPolicyObservationCensus.update(data: Data(
                "\(operationID.uuidString.lowercased())|\(scope.primitive.sequence)|\(attempt.closedResourceCount)|\(attempt.closedResourceCensusSHA256)\n".utf8))
        }
        retiringPolicyObservations.removeAll()
    }

    private func held(_ descriptor: Int32) throws -> EraseColdControlLeafFactV1 {
        try requireCurrent()
        var value = stat()
        let result = Darwin.fstat(descriptor, &value)
        let saved = errno
        try requireCurrent()
        guard result == 0 else { _ = saved; throw DiagnosticsFailure.invalidFile }
        return EraseColdControlLeafFactV1(value)
    }

    private func named(_ parent: Int32, _ name: String) throws -> EraseColdControlLeafFactV1? {
        try requireCurrent()
        var value = stat()
        let result = Darwin.fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW)
        let saved = errno
        try requireCurrent()
        if result != 0 {
            guard saved == ENOENT else { throw DiagnosticsFailure.invalidFile }
            return nil
        }
        return EraseColdControlLeafFactV1(value)
    }

    private func supportFact() throws -> EraseColdControlLeafFactV1 {
        let issuer = try requireIssuerAssociation()
        let actual = try held(issuer.borrowedSupport)
        var value = stat()
        try requireCurrent()
        let result = Darwin.lstat(candidate.applicationSupportURL.path, &value)
        let saved = errno
        try requireCurrent()
        guard result == 0, actual == EraseColdControlLeafFactV1(value),
              actual.mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              actual.links > 0, actual.user == Darwin.geteuid() else {
            _ = saved; throw DiagnosticsFailure.invalidFile
        }
        return actual
    }

    private func openDirectory(expected: EraseColdControlLeafFactV1) throws {
        let issuer = try requireIssuerAssociation()
        guard directory == nil else { throw DiagnosticsFailure.invalidFile }
        let resource = try makeResource(.directory)
        directory = resource
        _ = try syscall(.openDirectory, body: {
            Int64(Darwin.openat(issuer.borrowedSupport, Self.directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        }, retain: { result, _ in
            if result >= 0 { resource.openedDescriptor = Int32(result); resource.descriptor = Int32(result); resource.state = .open }
            else { resource.state = .uncertain }
        }, proof: { result, _ in
            guard result >= 0,
                  try self.held(Int32(result)) == expected,
                  try self.named(issuer.borrowedSupport, Self.directoryName) == expected else {
                throw DiagnosticsFailure.invalidFile
            }
            resource.fact = expected
            return nil
        })
    }

    private func observePolicy(_ kind: OwnedFileKindV1, at url: URL,
        fact: EraseColdControlLeafFactV1, sha256: String? = nil) throws
        -> ColdDiagnosticsPolicySnapshotV1 {
        try requireCurrent()
        guard policyObservationScope == nil, retiringPolicyObservations.count < 2 else {
            throw DiagnosticsFailure.sizeLimitExceeded
        }
        let support = ColdDiagnosticsPolicyNodeV1.Ancestor(
            url: candidate.applicationSupportURL, fact: try supportFact())
        let node: ColdDiagnosticsPolicyNodeV1
        if kind == .stagingDirectory {
            guard url == candidate.diagnosticsURL, sha256 == nil else {
                throw DiagnosticsFailure.invalidFile
            }
            node = ColdDiagnosticsPolicyNodeV1(kind: kind, url: url, fact: fact,
                byteCount: nil, sha256: nil, ancestors: [support])
        } else {
            guard (kind == .diagnostics && url == candidate.diagnosticsURL.appendingPathComponent(Self.currentName))
                || (kind == .temporaryFile && url == candidate.diagnosticsURL.appendingPathComponent(Self.temporaryName)),
                  let sha256, sha256.count == 64 else { throw DiagnosticsFailure.invalidFile }
            let root = try held(directoryDescriptor())
            node = ColdDiagnosticsPolicyNodeV1(kind: kind, url: url, fact: fact,
                byteCount: fact.size, sha256: sha256,
                ancestors: [support, ColdDiagnosticsPolicyNodeV1.Ancestor(
                    url: candidate.diagnosticsURL, fact: root)])
        }
        let frame = try begin(.observePolicy(kind: kind, at: url))
        let scope = ColdDiagnosticsPolicyObservationScopeV1(io: self,
            primitive: frame.intent, node: node)
        policyObservationScope = scope
        let value = try ProtectedFilePolicyV1.observeColdDiagnosticsPolicy(kind, at: url, scope: scope)
        try scope.requireCompleted()
        guard let attempt = scope.actualAttempt, scope.value == value else {
            throw DiagnosticsFailure.invalidFile
        }
        _ = try capture(.policyObservation(attempt), frame: frame)
        try requireCurrent()
        guard Self.snapshot(value, matches: Self.fullFact(fact)),
              value.isDirectory == (kind == .stagingDirectory) else {
            throw DiagnosticsFailure.invalidFile
        }
        try complete(frame)
        try scope.revokeAfterConsumption()
        retiringPolicyObservations.append(scope); policyObservationScope = nil
        return value
    }

    private func enumerate() throws -> [String] {
        guard enumeration == nil else { throw DiagnosticsFailure.invalidFile }
        let root = try directoryDescriptor()
        let resource = try makeResource(.enumeration)
        _ = try syscall(.openDirectory, body: {
            Int64(Darwin.openat(root, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        }, retain: { result, _ in
            if result >= 0 { resource.openedDescriptor = Int32(result); resource.descriptor = Int32(result); resource.state = .open }
            else { resource.state = .uncertain }
        }, proof: { result, _ in
            guard result >= 0, try self.held(Int32(result)) == self.held(root) else {
                throw DiagnosticsFailure.invalidFile
            }
            return nil
        })
        let attempt = ColdDiagnosticsEnumerationAttemptV1(io: self, resource: resource)
        enumeration = attempt // Retain before fdopendir/first readdir.
        let frame = try begin(.enumerateDirectory)
        let fd = try descriptor(resource)
        let stream = Darwin.fdopendir(fd)
        let openedErrno = errno
        attempt.fdopendirErrno = openedErrno
        attempt.fdopendirReturn = stream.map { UInt(bitPattern: $0) }
        guard let stream else { attempt.state = .uncertain; throw DiagnosticsFailure.invalidFile }
        // fdopendir consumed the FD on success. Only closedir may close it.
        resource.descriptor = nil; resource.directoryStream = stream
        resource.state = .directoryStream; attempt.state = .streamOwned
        var names: [String] = []
        while true {
            try requireCurrent()
            errno = 0
            let entry = Darwin.readdir(stream)
            let saved = errno
            attempt.readdirErrnos.append(saved)
            if let entry { attempt.actualReads.append(.entry(address: UInt(bitPattern: entry), savedErrno: saved)) }
            else { attempt.actualReads.append(.eof(savedErrno: saved)) }
            guard attempt.readdirErrnos.count <= 5 else { throw DiagnosticsFailure.invalidFile }
            try requireCurrent()
            guard let entry else {
                guard saved == 0 else { throw DiagnosticsFailure.invalidFile }
                attempt.reachedEOF = true; break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard name == Self.currentName || name == Self.temporaryName,
                  names.count < 2, !names.contains(name) else { throw DiagnosticsFailure.invalidFile }
            names.append(name)
        }
        attempt.names = names.sorted()
        try requireCurrent()
        resource.fencedDirectoryStream = stream
        resource.directoryStream = nil; resource.state = .closeEntered
        let closed = Darwin.closedir(stream)
        let closedErrno = errno
        resource.closeResult = closed; resource.closeErrno = closedErrno
        attempt.closeResult = closed; attempt.closeErrno = closedErrno
        resource.closedByIntent = frame.intent
        resource.state = closed == 0 ? .closed : .uncertain
        attempt.state = closed == 0 ? .closed : .uncertain
        guard closed == 0 else { throw DiagnosticsFailure.invalidFile }
        _ = try capture(.enumeration(attempt), frame: frame)
        try attempt.requireCheckedSettlement()
        try complete(frame)
        guard retiringResources.count < 3, retiringEnumerations.count < 2 else {
            throw DiagnosticsFailure.sizeLimitExceeded
        }
        retiringResources.append(resource); retiringEnumerations.append(attempt)
        enumeration = nil
        return attempt.names
    }

    private func leaf(_ name: String, expected: EraseColdControlLeafFactV1,
        parent: EraseColdControlLeafFactV1) throws -> ColdDiagnosticsPhysicalLeafV1 {
        guard observer == nil, expected.size >= 0,
              expected.size <= Int64(candidate.canonicalBytes.count),
              Self.safeRegular(expected, parent: parent) else { throw DiagnosticsFailure.invalidFile }
        let root = try directoryDescriptor()
        let resource = try makeResource(.observer)
        observer = resource
        let kind: ColdDiagnosticsPrimitiveIntentV1.Kind =
            name == Self.currentName ? .openCurrent : .openTemporary
        _ = try syscall(kind, body: {
            Int64(Darwin.openat(root, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC))
        }, retain: { result, _ in
            if result >= 0 { resource.openedDescriptor = Int32(result); resource.descriptor = Int32(result); resource.state = .open }
            else { resource.state = .uncertain }
        }, proof: { result, _ in
            guard result >= 0, try self.held(Int32(result)) == expected,
                  try self.named(root, name) == expected else { throw DiagnosticsFailure.invalidFile }
            resource.fact = expected; return nil
        })
        let fd = try descriptor(resource)
        var digest = SHA256()
        var offset: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while offset < UInt64(expected.size) {
            let count = min(UInt64(buffer.count), UInt64(expected.size) - offset)
            let readOffset = offset
            let readCount = try syscall(.read(resourceID: resource.id,
                offset: readOffset, maximumCount: count), body: {
                buffer.withUnsafeMutableBytes {
                    Int64(Darwin.pread(fd, $0.baseAddress, Int(count), off_t(readOffset)))
                }
            }, proof: { result, _ in
                guard result > 0, result <= Int64(count),
                      try self.held(fd) == expected,
                      try self.named(root, name) == expected else { throw DiagnosticsFailure.invalidFile }
                let identical = self.candidate.canonicalBytes.withUnsafeBytes { source in
                    buffer.withUnsafeBytes { actual in
                        memcmp(source.baseAddress!.advanced(by: Int(readOffset)),
                            actual.baseAddress!, Int(result)) == 0
                    }
                }
                guard identical else { throw DiagnosticsFailure.invalidFile }
                return nil
            })
            digest.update(data: Data(buffer.prefix(Int(readCount))))
            offset += UInt64(readCount)
        }
        var extra: UInt8 = 0
        _ = try syscall(.read(resourceID: resource.id, offset: offset, maximumCount: 1), body: {
            Int64(Darwin.pread(fd, &extra, 1, off_t(offset)))
        }, proof: { result, _ in
            guard result == 0, try self.held(fd) == expected,
                  try self.named(root, name) == expected else { throw DiagnosticsFailure.invalidFile }
            return nil
        })
        let sha = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let policy = try observePolicy(name == Self.currentName ? .diagnostics : .temporaryFile,
            at: candidate.diagnosticsURL.appendingPathComponent(name), fact: expected, sha256: sha)
        guard try held(fd) == expected, try named(root, name) == expected else {
            throw DiagnosticsFailure.invalidFile
        }
        try close(resource, retire: true)
        observer = nil
        return ColdDiagnosticsPhysicalLeafV1(name: name, fact: expected, sha256: sha, policy: policy)
    }

    private func observeImage() throws -> ColdDiagnosticsPhysicalImageV1 {
        let issuer = try requireIssuerAssociation()
        let support = try supportFact()
        guard let namedDirectory = try named(issuer.borrowedSupport, Self.directoryName) else {
            guard directory == nil else { throw DiagnosticsFailure.invalidFile }
            return ColdDiagnosticsPhysicalImageV1(supportFact: support, directoryFact: nil,
                directoryPolicy: nil, directoryNames: [], leaves: [])
        }
        guard Self.safeDirectory(namedDirectory),
              namedDirectory.device == support.device,
              namedDirectory.user == support.user,
              namedDirectory.group == Self.childGroup(support) else { throw DiagnosticsFailure.invalidFile }
        if directory == nil { try openDirectory(expected: namedDirectory) }
        let root = try directoryDescriptor()
        guard try held(root) == namedDirectory else { throw DiagnosticsFailure.invalidFile }
        let names = try enumerate()
        // The admitted cuts never contain temp and current simultaneously.
        guard names.count <= 1 else { throw DiagnosticsFailure.invalidFile }
        var leaves: [ColdDiagnosticsPhysicalLeafV1] = []
        for name in names {
            guard let fact = try named(root, name) else { throw DiagnosticsFailure.invalidFile }
            leaves.append(try leaf(name, expected: fact, parent: namedDirectory))
        }
        let policy = try observePolicy(.stagingDirectory, at: candidate.diagnosticsURL,
            fact: namedDirectory)
        guard try held(root) == namedDirectory,
              try named(issuer.borrowedSupport, Self.directoryName) == namedDirectory,
              try supportFact() == support, try enumerate() == names else {
            throw DiagnosticsFailure.invalidFile
        }
        let image = ColdDiagnosticsPhysicalImageV1(supportFact: support,
            directoryFact: namedDirectory, directoryPolicy: policy,
            directoryNames: names, leaves: leaves)
        // Unknown/unrequested raw policy belongs only to the closed owned
        // birth/partial REQUEST grammar. Completed C/K/current cannot adopt it.
        if mode != .replaceWithCanonicalZero || names == [Self.currentName] {
            guard policy.compatibleReadback != nil,
                  leaves.allSatisfy({ $0.policy.compatibleReadback != nil }) else {
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
        }
        return image
    }

    private func unchangedImage() throws -> ColdDiagnosticsPhysicalImageV1 {
        let issuer = try requireIssuerAssociation()
        guard let before = currentImage else { throw DiagnosticsFailure.invalidFile }
        let fresh = try observeImage()
        guard fresh == before else { throw DiagnosticsFailure.concurrentMutation }
        try issuer.requireCheckedIO(self)
        try retireObservedResources()
        return fresh
    }

    private func requirePrefix(_ prefix: ColdDiagnosticsPrefixV1,
        image: ColdDiagnosticsPhysicalImageV1) throws {
        switch prefix {
        case .absentDirectory:
            guard image.directoryFact == nil, image.directoryPolicy == nil,
                  image.directoryNames.isEmpty, image.leaves.isEmpty else {
                throw DiagnosticsFailure.invalidFile
            }
        case .emptyDirectory:
            guard image.directoryFact != nil, image.directoryPolicy != nil,
                  image.directoryNames.isEmpty, image.leaves.isEmpty else {
                throw DiagnosticsFailure.invalidFile
            }
        case .temporary(let written, let accepted):
            guard written <= UInt64(candidate.canonicalBytes.count),
                  image.directoryNames == [Self.temporaryName], image.leaves.count == 1,
                  image.leaves[0].name == Self.temporaryName,
                  image.leaves[0].fact.size == Int64(written),
                  !accepted || written == UInt64(candidate.canonicalBytes.count) else {
                throw DiagnosticsFailure.invalidFile
            }
        case .published, .completedObservation:
            guard image.directoryNames == [Self.currentName], image.leaves.count == 1,
                  image.leaves[0].name == Self.currentName,
                  image.leaves[0].fact.size == Int64(candidate.canonicalBytes.count),
                  image.leaves[0].sha256 == candidate.sha256 else {
                throw DiagnosticsFailure.invalidFile
            }
        }
    }

    private func directoryMutation(_ before: ColdDiagnosticsPhysicalImageV1,
        _ after: ColdDiagnosticsPhysicalImageV1) throws {
        guard Self.immutable(before.supportFact, after.supportFact),
              let a = before.directoryFact, let b = after.directoryFact,
              Self.immutable(a, b), before.directoryPolicy == after.directoryPolicy else {
            throw DiagnosticsFailure.concurrentMutation
        }
    }

    private func requestPolicy(_ kind: ColdDiagnosticsPrimitiveIntentV1.Kind,
        selectedName: String?) throws {
        let before = try unchangedImage()
        guard mode != .observeCompletedZero, policyScope == nil,
              policyScopes.count < 2, let rootFact = before.directoryFact else {
            throw DiagnosticsFailure.invalidFile
        }
        if let selectedName {
            guard (selectedName == Self.currentName && kind == .requestPublishedPolicy)
                || (selectedName == Self.temporaryName && kind == .requestTemporaryPolicy) else {
                throw DiagnosticsFailure.invalidFile
            }
        } else {
            guard kind == .requestDirectoryPolicy else { throw DiagnosticsFailure.invalidFile }
        }
        if mode == .requestCompletedZeroPolicy {
            try requirePrefix(.completedObservation, image: before)
            if policyScopes.isEmpty {
                guard selectedName == nil, kind == .requestDirectoryPolicy else {
                    throw DiagnosticsFailure.invalidFile
                }
            } else {
                guard policyScopes.count == 1, selectedName == Self.currentName,
                      kind == .requestPublishedPolicy,
                      policyScopes[0].primitive.kind == .requestDirectoryPolicy else {
                    throw DiagnosticsFailure.invalidFile
                }
                try policyScopes[0].requireRevokedSettlement()
            }
        }
        let support = ColdDiagnosticsPolicyNodeV1.Ancestor(
            url: candidate.applicationSupportURL, fact: before.supportFact)
        let node: ColdDiagnosticsPolicyNodeV1
        if let selectedName {
            guard let leaf = before.leaves.first(where: { $0.name == selectedName }) else {
                throw DiagnosticsFailure.invalidFile
            }
            node = ColdDiagnosticsPolicyNodeV1(
                kind: selectedName == Self.currentName ? .diagnostics : .temporaryFile,
                url: candidate.diagnosticsURL.appendingPathComponent(selectedName), fact: leaf.fact,
                byteCount: Int64(leaf.fact.size), sha256: leaf.sha256,
                ancestors: [support, ColdDiagnosticsPolicyNodeV1.Ancestor(
                    url: candidate.diagnosticsURL, fact: rootFact)])
        } else {
            node = ColdDiagnosticsPolicyNodeV1(kind: .stagingDirectory,
                url: candidate.diagnosticsURL, fact: rootFact,
                byteCount: nil, sha256: nil, ancestors: [support])
        }
        let frame = try begin(kind, mutation: true)
        let scope = ColdDiagnosticsPolicyEffectScopeV1(io: self,
            primitive: frame.intent, node: node)
        policyScope = scope; policyScopes.append(scope)
        try ProtectedFilePolicyV1.applyAndVerifyColdDiagnostics(node.kind, at: node.url, scope: scope)
        try scope.requireCompleted()
        _ = try capture(.policy(scope), frame: frame)
        let after = try observeImage()
        guard after.supportFact == before.supportFact,
              after.directoryNames == before.directoryNames,
              after.leaves.count == before.leaves.count else { throw DiagnosticsFailure.concurrentMutation }
        if let selectedName {
            guard after.directoryFact == before.directoryFact,
                  after.directoryPolicy == before.directoryPolicy,
                  let old = before.leaves.first(where: { $0.name == selectedName }),
                  let new = after.leaves.first(where: { $0.name == selectedName }),
                  Self.ctimeOnly(Self.fullFact(new.fact), from: Self.fullFact(old.fact)),
                  Self.fullFact(new.fact) == scope.finalFullFact,
                  new.sha256 == old.sha256, new.policy.compatibleReadback == scope.value,
                  new.policy.volumeSupportsProtection == old.policy.volumeSupportsProtection else {
                throw DiagnosticsFailure.concurrentMutation
            }
            acceptedLeafPolicy = scope.value
        } else {
            guard after.leaves == before.leaves, let new = after.directoryFact,
                  Self.ctimeOnly(Self.fullFact(new), from: Self.fullFact(rootFact)),
                  Self.fullFact(new) == scope.finalFullFact,
                  after.directoryPolicy?.compatibleReadback == scope.value,
                  after.directoryPolicy?.volumeSupportsProtection == before.directoryPolicy?.volumeSupportsProtection else {
                throw DiagnosticsFailure.concurrentMutation
            }
            acceptedDirectoryPolicy = scope.value
        }
        try complete(frame, after: after)
        try scope.revokeAfterConsumption()
        policyScope = nil
    }

    private func openSelected(_ name: String) throws -> ColdDiagnosticsResourceV1 {
        let before = try unchangedImage()
        guard let selected = before.leaves.first(where: { $0.name == name }),
              name == Self.temporaryName || name == Self.currentName else {
            throw DiagnosticsFailure.invalidFile
        }
        let resource = try makeResource(name == Self.temporaryName ? .temporary : .current)
        if name == Self.temporaryName { temporary = resource } else { current = resource }
        let root = try directoryDescriptor()
        _ = try syscall(name == Self.temporaryName ? .openTemporary : .openCurrent, body: {
            Int64(Darwin.openat(root, name,
                (name == Self.temporaryName ? O_RDWR : O_RDONLY)
                    | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC))
        }, retain: { result, _ in
            if result >= 0 { resource.openedDescriptor = Int32(result); resource.descriptor = Int32(result); resource.state = .open }
            else { resource.state = .uncertain }
        }, proof: { result, _ in
            guard result >= 0, try self.held(Int32(result)) == selected.fact,
                  try self.named(root, name) == selected.fact else { throw DiagnosticsFailure.invalidFile }
            resource.fact = selected.fact; return nil
        })
        return resource
    }

    private func syncFile(_ resource: ColdDiagnosticsResourceV1) throws {
        let before = try unchangedImage()
        let fd = try descriptor(resource)
        guard let leaf = before.leaves.first, try held(fd) == leaf.fact else {
            throw DiagnosticsFailure.invalidFile
        }
        _ = try syscall(.syncFile(resourceID: resource.id), mutation: true,
            body: { Int64(Darwin.fsync(fd)) }, proof: { result, _ in
                guard result == 0 else { throw DiagnosticsFailure.invalidFile }
                let after = try self.observeImage()
                guard after == before else { throw DiagnosticsFailure.concurrentMutation }
                return after
            })
    }

    private func syncDirectory() throws {
        let before = try unchangedImage()
        let fd = try directoryDescriptor()
        _ = try syscall(.syncDirectory, mutation: true,
            body: { Int64(Darwin.fsync(fd)) }, proof: { result, _ in
                guard result == 0 else { throw DiagnosticsFailure.invalidFile }
                let after = try self.observeImage()
                guard after == before else { throw DiagnosticsFailure.concurrentMutation }
                return after
            })
    }

    private func createDirectory() throws {
        let issuer = try requireIssuerAssociation()
        let before = try unchangedImage()
        try requirePrefix(.absentDirectory, image: before)
        _ = try syscall(.createDirectory, mutation: true, body: {
            Int64(Darwin.mkdirat(issuer.borrowedSupport, Self.directoryName, mode_t(0o700)))
        }, proof: { result, _ in
            guard result == 0 else { throw DiagnosticsFailure.invalidFile }
            let after = try self.observeImage()
            try self.requirePrefix(.emptyDirectory, image: after)
            guard Self.immutable(before.supportFact, after.supportFact) else {
                throw DiagnosticsFailure.concurrentMutation
            }
            return after
        })
        // The actual created directory and its parent publication must be
        // durable; borrowed Support remains owned/closed by main alone.
        let parentBefore = try unchangedImage()
        _ = try syscall(.syncSupport, mutation: true,
            body: { Int64(Darwin.fsync(issuer.borrowedSupport)) }, proof: { result, _ in
                guard result == 0 else { throw DiagnosticsFailure.invalidFile }
                let after = try self.observeImage()
                guard after == parentBefore else { throw DiagnosticsFailure.concurrentMutation }
                return after
            })
    }

    private func createTemporary() throws -> ColdDiagnosticsResourceV1 {
        let before = try unchangedImage()
        try requirePrefix(.emptyDirectory, image: before)
        let root = try directoryDescriptor()
        let resource = try makeResource(.temporary)
        temporary = resource
        _ = try syscall(.createTemporary, mutation: true, body: {
            Int64(Darwin.openat(root, Self.temporaryName,
                O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600)))
        }, retain: { result, _ in
            if result >= 0 { resource.openedDescriptor = Int32(result); resource.descriptor = Int32(result); resource.state = .open }
            else { resource.state = .uncertain }
        }, proof: { result, _ in
            guard result >= 0 else { throw DiagnosticsFailure.invalidFile }
            let after = try self.observeImage()
            try self.requirePrefix(.temporary(writtenCount: 0, policyAccepted: false), image: after)
            try self.directoryMutation(before, after)
            guard after.leaves[0].fact == (try self.held(Int32(result))) else {
                throw DiagnosticsFailure.invalidFile
            }
            resource.fact = after.leaves[0].fact
            return after
        })
        return resource
    }

    private func writeRemaining(_ resource: ColdDiagnosticsResourceV1) throws {
        let fd = try descriptor(resource)
        while true {
            let before = try unchangedImage()
            guard before.directoryNames == [Self.temporaryName], let old = before.leaves.first,
                  old.fact == (try self.held(fd)), old.fact.size >= 0 else { throw DiagnosticsFailure.invalidFile }
            let offset = UInt64(old.fact.size)
            let total = UInt64(candidate.canonicalBytes.count)
            guard offset <= total else { throw DiagnosticsFailure.invalidFile }
            if offset == total { break }
            let count = min(UInt64(65_536), total - offset)
            _ = try syscall(.write(resourceID: resource.id, offset: offset, count: count),
                mutation: true, body: {
                    candidate.canonicalBytes.withUnsafeBytes {
                        Int64(Darwin.pwrite(fd, $0.baseAddress!.advanced(by: Int(offset)),
                            Int(count), off_t(offset)))
                    }
                }, proof: { result, _ in
                    guard result > 0, result <= Int64(count) else { throw DiagnosticsFailure.invalidFile }
                    let after = try self.observeImage()
                    try self.requirePrefix(.temporary(writtenCount: offset + UInt64(result),
                        policyAccepted: false), image: after)
                    guard after.supportFact == before.supportFact,
                          after.directoryFact == before.directoryFact,
                          after.directoryPolicy == before.directoryPolicy,
                          let new = after.leaves.first,
                          Self.immutable(old.fact, new.fact), new.fact.links == old.fact.links,
                          new.policy == old.policy, try self.held(fd) == new.fact else {
                        throw DiagnosticsFailure.concurrentMutation
                    }
                    return after
                })
        }
    }

    private func publish() throws {
        let before = try unchangedImage()
        try requirePrefix(.temporary(writtenCount: UInt64(candidate.canonicalBytes.count),
            policyAccepted: true), image: before)
        try requireAcceptedPolicy(before, observationOnly: false)
        let root = try directoryDescriptor()
        guard try named(root, Self.currentName) == nil else { throw DiagnosticsFailure.invalidFile }
        _ = try syscall(.publishTemporary, mutation: true, body: {
            Int64(Darwin.renameatx_np(root, Self.temporaryName, root, Self.currentName,
                UInt32(RENAME_EXCL)))
        }, proof: { result, _ in
            guard result == 0 else { throw DiagnosticsFailure.invalidFile }
            let after = try self.observeImage()
            try self.requirePrefix(.published, image: after)
            try self.directoryMutation(before, after)
            guard after.supportFact == before.supportFact,
                  let old = before.leaves.first, let new = after.leaves.first,
                  Self.ctimeOnly(Self.fullFact(new.fact), from: Self.fullFact(old.fact)),
                  new.sha256 == old.sha256, new.policy == old.policy else {
                throw DiagnosticsFailure.concurrentMutation
            }
            return after
        })
    }

    private func requireAcceptedPolicy(_ image: ColdDiagnosticsPhysicalImageV1,
        observationOnly: Bool) throws {
        guard let directoryPolicy = image.directoryPolicy, let leaf = image.leaves.first,
              image.leaves.count == 1 else { throw DiagnosticsFailure.invalidFile }
        if observationOnly {
            guard directoryPolicy.compatibleReadback != nil, leaf.policy.compatibleReadback != nil else {
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
            if directoryPolicy.compatibleReadback?.state != .strictComplete
                || leaf.policy.compatibleReadback?.state != .strictComplete {
                let issuer = try requireIssuerAssociation()
                // This invokes only the genuine owner's retained same-process
                // prerequisite join. A pending DATA image cannot satisfy it.
                try issuer.requireCompletedPolicyObservation(io: self, actualImage: image)
            }
        } else {
            guard directoryPolicy.compatibleReadback?.state == .strictComplete
                    || (acceptedDirectoryPolicy != nil && directoryPolicy.compatibleReadback == acceptedDirectoryPolicy),
                  leaf.policy.compatibleReadback?.state == .strictComplete
                    || (acceptedLeafPolicy != nil && leaf.policy.compatibleReadback == acceptedLeafPolicy) else {
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
        }
    }

    func performChecked() throws -> ColdDiagnosticsCheckedReceiptV1 {
        let issuer = try requireIssuerAssociation()
        guard state == .registered, !frameEntered, resources.isEmpty, receipt == nil else {
            throw DiagnosticsFailure.invalidFile
        }
        retainedIssuer = issuer
        try issuer.requireHeld(); try issuer.requireCheckedIO(self)
        guard candidate.applicationSupportURL.isFileURL, candidate.diagnosticsURL.isFileURL,
              candidate.applicationSupportURL.standardizedFileURL == candidate.applicationSupportURL,
              candidate.diagnosticsURL.standardizedFileURL == candidate.diagnosticsURL,
              candidate.diagnosticsURL.lastPathComponent == Self.directoryName,
              candidate.diagnosticsURL.deletingLastPathComponent() == candidate.applicationSupportURL,
              candidate.canonicalBytes == issuer.expectedCanonicalBytes else {
            throw DiagnosticsFailure.invalidFile
        }
        try DiagnosticsStore.requireColdCanonicalZero(candidate.canonicalBytes,
            generatedAt: candidate.generatedAt)
        formatLease.lock()
        frameEntered = true; state = .performing
        defer { frameEntered = false; formatLease.unlock() }
        do {
            let initial = try observeImage()
            currentImage = initial
            try requirePrefix(issuer.expectedPrefix, image: initial)
            // Main independently rejoins the actual authenticated prefix/root
            // facts. This fresh observation never becomes its own authority.
            try issuer.requireCheckedIO(self)
            try retireObservedResources()
            switch mode {
            case .observeCompletedZero:
                guard issuer.expectedPrefix == .completedObservation else {
                    throw DiagnosticsFailure.invalidFile
                }
                try requireAcceptedPolicy(initial, observationOnly: true)
            case .requestCompletedZeroPolicy:
                guard issuer.expectedPrefix == .completedObservation else {
                    throw DiagnosticsFailure.invalidFile
                }
                // Admission to this distinct route requires the immutable K
                // request in main. Every fresh prefix executes NEW real root
                // then current setters, including an indistinguishable no-op.
                try requestPolicy(.requestDirectoryPolicy, selectedName: nil)
                try requestPolicy(.requestPublishedPolicy, selectedName: Self.currentName)
                try requireCompletedPolicySequence()
            case .replaceWithCanonicalZero:
                guard issuer.expectedPrefix != .completedObservation else {
                    throw DiagnosticsFailure.invalidFile
                }
                try requireCurrent()
                try candidate.storagePreflight.checkDeviceOperationalWrite(
                    byteCount: UInt64(candidate.canonicalBytes.count),
                    onVolumeContaining: candidate.applicationSupportURL)
                try requireCurrent()
                if issuer.expectedPrefix == .absentDirectory { try createDirectory() }
                guard let image = currentImage, image.directoryFact != nil else {
                    throw DiagnosticsFailure.invalidFile
                }
                // A fresh real request is mandatory for any pending Simulator
                // directory shape; an authenticated prefix alone is no policy.
                if issuer.expectedPrefix == .absentDirectory
                    || image.directoryPolicy?.compatibleReadback?.state != .strictComplete {
                    try requestPolicy(.requestDirectoryPolicy, selectedName: nil)
                }
                if currentImage?.directoryNames == [Self.currentName] {
                    let resource = try openSelected(Self.currentName)
                    if currentImage?.leaves.first?.policy.compatibleReadback?.state != .strictComplete {
                        try requestPolicy(.requestPublishedPolicy, selectedName: Self.currentName)
                    }
                    try syncFile(resource)
                } else {
                    let resource: ColdDiagnosticsResourceV1
                    if currentImage?.directoryNames.isEmpty == true {
                        resource = try createTemporary()
                    } else { resource = try openSelected(Self.temporaryName) }
                    try writeRemaining(resource)
                    try syncFile(resource)
                    // Both actual setters/readback and checked PFP settlement
                    // precede exclusive publication, including full-temp replay.
                    try requestPolicy(.requestTemporaryPolicy, selectedName: Self.temporaryName)
                    try syncFile(resource)
                    try publish()
                }
                try syncDirectory()
            }
            let final = try unchangedImage()
            try requirePrefix(mode == .replaceWithCanonicalZero ? .published : .completedObservation,
                image: final)
            try requireAcceptedPolicy(final, observationOnly: mode == .observeCompletedZero)
            guard stack.isEmpty, observer == nil, enumeration == nil, policyScope == nil,
                  policyObservationScope == nil, uncertainPolicyObservationScope == nil else {
                throw DiagnosticsFailure.invalidFile
            }
            if let temporary {
                guard try held(descriptor(temporary)) == final.leaves[0].fact else {
                    throw DiagnosticsFailure.invalidFile
                }
                try close(temporary)
            }
            if let current {
                guard try held(descriptor(current)) == final.leaves[0].fact else {
                    throw DiagnosticsFailure.invalidFile
                }
                try close(current)
            }
            guard let directory else { throw DiagnosticsFailure.invalidFile }
            let rootFD = try descriptor(directory)
            guard try held(rootFD) == final.directoryFact,
                  try named(issuer.borrowedSupport, Self.directoryName) == final.directoryFact,
                  try named(rootFD, Self.currentName) == final.leaves[0].fact,
                  try named(rootFD, Self.temporaryName) == nil,
                  try supportFact() == final.supportFact else {
                throw DiagnosticsFailure.concurrentMutation
            }
            try close(directory)
            guard resources.allSatisfy({ $0.state == .closed && $0.closeResult == 0
                && $0.closeErrno != nil && $0.descriptor == nil && $0.directoryStream == nil }),
                  stack.isEmpty, retiringResources.isEmpty, retiringEnumerations.isEmpty,
                  retiringPolicyObservations.isEmpty, policyObservationScope == nil,
                  uncertainPolicyObservationScope == nil,
                  uncertainPolicyDescriptors.isEmpty else {
                throw DiagnosticsFailure.invalidFile
            }
            let digest = closedResourceCensus.finalize().map { String(format: "%02x", $0) }.joined()
            finalClosedResourceCensusSHA256 = digest
            let policyDigest = closedPolicyObservationCensus.finalize()
                .map { String(format: "%02x", $0) }.joined()
            finalPolicyObservationCensusSHA256 = policyDigest
            let actual = ColdDiagnosticsCheckedReceiptV1(io: self, image: final,
                closedResourceIDs: resources.map(\.id), closedResourceCount: closedResourceCount,
                censusSHA256: digest, policyObservationCount: closedPolicyObservationCount,
                policyObservationResourceCount: closedPolicyObservationResourceCount,
                policyObservationCensusSHA256: policyDigest)
            receipt = actual; state = .checkedClosed
            try issuer.requireCheckedReceipt(actual, io: self)
            return actual
        } catch {
            poison()
            #if DEBUG
            print("Cold diagnostics boundary=\(ColdDiagnosticsBoundaryLabelV1.project(lastBoundary)) sequence=\(sequence) mode=\(mode)")
            #endif
            // Actual unresolved owners/FDs/streams/policy attempts remain
            // retained. No ordinary recovery, unchecked close or retry occurs.
            throw error
        }
    }

    func requireIssuerCheckedSettlement(receipt: ColdDiagnosticsCheckedReceiptV1) throws {
        guard state == .checkedClosed, self.receipt === receipt,
              receipt.ioIdentity == ObjectIdentifier(self), receipt.operationID == operationID,
              receipt.currentImage == currentImage, receipt.canonicalSHA256 == candidate.sha256,
              receipt.byteCount == UInt64(candidate.canonicalBytes.count),
              receipt.closedResourceCount == closedResourceCount,
              receipt.closedResourceCensusSHA256 == finalClosedResourceCensusSHA256,
              receipt.closedPolicyObservationCount == closedPolicyObservationCount,
              receipt.closedPolicyObservationResourceCount == closedPolicyObservationResourceCount,
              receipt.closedPolicyObservationCensusSHA256 == finalPolicyObservationCensusSHA256,
              receipt.closedResourceIDs == resources.map(\.id),
              resources.allSatisfy({ $0.state == .closed && $0.closeResult == 0
                  && $0.closeErrno != nil && $0.descriptor == nil && $0.directoryStream == nil }),
              stack.isEmpty, retiringResources.isEmpty, retiringEnumerations.isEmpty,
              retiringPolicyObservations.isEmpty, policyObservationScope == nil,
              uncertainPolicyObservationScope == nil,
              observer == nil, enumeration == nil, policyScope == nil,
              uncertainPolicyDescriptors.isEmpty else { throw DiagnosticsFailure.invalidFile }
        for scope in policyScopes { try scope.requireRevokedSettlement() }
    }

    func requireCheckedClosed() throws {
        let issuer = try requireIssuerAssociation()
        guard let receipt else { throw DiagnosticsFailure.invalidFile }
        try requireIssuerCheckedSettlement(receipt: receipt)
        try issuer.requireHeld(); try issuer.requireCheckedReceipt(receipt, io: self)
    }

    func cacheProjection(receipt: ColdDiagnosticsCheckedReceiptV1) throws
        -> ColdDiagnosticsCacheProjectionV1 {
        let issuer = try requireIssuerAssociation()
        try requireIssuerCheckedSettlement(receipt: receipt)
        try issuer.requireHeld(); try issuer.requireCheckedReceipt(receipt, io: self)
        try DiagnosticsStore.requireColdCanonicalZero(candidate.canonicalBytes,
            generatedAt: candidate.generatedAt)
        let projection = ColdDiagnosticsCacheProjectionV1(candidate: candidate)
        try issuer.requireHeld(); try issuer.requireCheckedReceipt(receipt, io: self)
        return projection
    }

    fileprivate func requireCompletedPolicySequence() throws {
        guard mode == .requestCompletedZeroPolicy, policyScopes.count == 2,
              policyScopes[0].primitive.kind == .requestDirectoryPolicy,
              policyScopes[0].node.kind == .stagingDirectory,
              policyScopes[0].node.url == candidate.diagnosticsURL,
              policyScopes[1].primitive.kind == .requestPublishedPolicy,
              policyScopes[1].node.kind == .diagnostics,
              policyScopes[1].node.url == candidate.diagnosticsURL.appendingPathComponent(Self.currentName),
              acceptedDirectoryPolicy != nil, acceptedLeafPolicy != nil else {
            throw DiagnosticsFailure.invalidFile
        }
        for scope in policyScopes { try scope.requireRevokedSettlement() }
    }

    fileprivate func requireLiveCompletedPolicyBinding(
        issuer: ColdEraseDiagnosticsEffectIssuerV1) throws {
        guard try requireIssuerAssociation() === issuer,
              retainedIssuer === issuer, state == .checkedClosed else {
            throw DiagnosticsFailure.invalidFile
        }
    }

    func completedPolicyReceipt(receipt: ColdDiagnosticsCheckedReceiptV1) throws
        -> ColdDiagnosticsCompletedPolicyReceiptV1 {
        let issuer = try requireIssuerAssociation()
        try requireIssuerCheckedSettlement(receipt: receipt)
        try requireCompletedPolicySequence()
        try issuer.requireHeld()
        try issuer.requireCompletedPolicyPrerequisite(io: self, receipt: receipt)
        if let existing = completedPolicyReceiptValue {
            try existing.requireCurrentProcessBinding(issuer: issuer, actualImage: receipt.currentImage)
            return existing
        }
        guard !completedPolicyReceiptMinted else { throw DiagnosticsFailure.invalidFile }
        let actual = ColdDiagnosticsCompletedPolicyReceiptV1(io: self, issuer: issuer, receipt: receipt)
        completedPolicyReceiptValue = actual; completedPolicyReceiptMinted = true
        try actual.requireCurrentProcessBinding(issuer: issuer, actualImage: receipt.currentImage)
        return actual
    }

    func releaseCompletedIssuerAssociation(issuer: ColdEraseDiagnosticsEffectIssuerV1) throws {
        guard !issuerReleased, self.issuer === issuer, retainedIssuer === issuer,
              let receipt else { throw DiagnosticsFailure.invalidFile }
        try requireIssuerCheckedSettlement(receipt: receipt)
        // Main's pure exact proof includes permanent route revocation and
        // consumption by every cache/current-owner/final settlement consumer.
        try issuer.requireCompletedIORelease(io: self, receipt: receipt)
        guard state == .checkedClosed, self.issuer === issuer, retainedIssuer === issuer else {
            throw DiagnosticsFailure.invalidFile
        }
        issuerReleased = true; self.issuer = nil; retainedIssuer = nil
    }

    fileprivate nonisolated static func fullFact(_ value: EraseColdControlLeafFactV1) -> String {
        "\(value.device)|\(value.inode)|\(value.mode)|\(value.user)|\(value.group)|\(value.links)|\(value.size)|\(value.modifiedSeconds)|\(value.modifiedNanoseconds)|\(value.changedSeconds)|\(value.changedNanoseconds)"
    }

    fileprivate nonisolated static func snapshot(_ value: ColdDiagnosticsPolicySnapshotV1,
        matches fact: String) -> Bool {
        let fields = fact.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 11, let device = UInt64(fields[0]),
              let inode = UInt64(fields[1]), let mode = UInt16(fields[2]),
              let links = UInt64(fields[5]) else { return false }
        return value.device == device && value.inode == inode
            && value.mode == mode && value.linkCount == links
    }

    fileprivate nonisolated static func ctimeOnly(_ actual: String, from before: String) -> Bool {
        let a = actual.split(separator: "|", omittingEmptySubsequences: false)
        let b = before.split(separator: "|", omittingEmptySubsequences: false)
        return a.count == 11 && b.count == 11 && a.prefix(9).elementsEqual(b.prefix(9))
    }

    private nonisolated static func immutable(_ a: EraseColdControlLeafFactV1,
        _ b: EraseColdControlLeafFactV1) -> Bool {
        a.device == b.device && a.inode == b.inode && a.mode == b.mode
            && a.user == b.user && a.group == b.group
    }

    private nonisolated static func childGroup(_ parent: EraseColdControlLeafFactV1) -> gid_t {
        parent.mode & mode_t(S_ISGID) != 0 ? parent.group : Darwin.getegid()
    }

    private nonisolated static func safeDirectory(_ fact: EraseColdControlLeafFactV1) -> Bool {
        fact.mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
            && (fact.mode & mode_t(0o7777) == mode_t(0o700)
                || fact.mode & mode_t(0o7777) == mode_t(0o2700))
            && fact.links > 0
    }

    private nonisolated static func safeRegular(_ fact: EraseColdControlLeafFactV1,
        parent: EraseColdControlLeafFactV1) -> Bool {
        fact.mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            && fact.mode & mode_t(0o7777) == mode_t(0o600)
            && fact.links == 1 && fact.device == parent.device
            && fact.user == parent.user && fact.group == childGroup(parent)
    }
}

enum DiagnosticsFailure: Error, Equatable {
    case invalidFile
    case protectedDataUnavailable
    case sizeLimitExceeded
    case unsupportedVersion
    case recoveryRequired
    case concurrentMutation
}

typealias DeviceOperationalSupportStoreV1 = DiagnosticsStore

/// C54 does not add a diagnostics store, record kind, or persistence writer.
/// This declaration keeps the store's exclusion and lifecycle ownership
/// explicit while preserving the existing counters and health schema.
enum C54EncryptedPortableEnvelopeDiagnosticsStoreBoundaryV1 {
    static let diagnosticsAreMetadataOnly = true
    static let createsPersistentEnvelopeRecord = false
    static let persistsEnvelopeBytes = false
    static let envelopeBytesExported = false
    static let persistsPassphrases = false
    static let passphrasesExported = false
    static let persistsDerivedKeys = false
    static let derivedKeysExported = false
    static let persistsSaltsOrNonces = false
    static let saltsOrNoncesExported = false
    static let persistsPlaintextOrCustomerDigests = false
    static let plaintextOrCustomerDigestsExported = false
    static let persistsRawMetadata = false
    static let rawMetadataExported = false
    static let persistsLinkableIDsOrFilenames = false
    static let linkableIDsOrFilenamesExported = false
    static let persistsScratchPaths = false
    static let scratchPathsExported = false
    static let preservesExistingCounters = true
    static let customerDataExported = false
    static let diagnosticsOwnCleanup = false

    static func validate() -> Bool {
        diagnosticsAreMetadataOnly
            && !createsPersistentEnvelopeRecord
            && !persistsEnvelopeBytes
            && !envelopeBytesExported
            && !persistsPassphrases
            && !passphrasesExported
            && !persistsDerivedKeys
            && !derivedKeysExported
            && !persistsSaltsOrNonces
            && !saltsOrNoncesExported
            && !persistsPlaintextOrCustomerDigests
            && !plaintextOrCustomerDigestsExported
            && !persistsRawMetadata
            && !rawMetadataExported
            && !persistsLinkableIDsOrFilenames
            && !linkableIDsOrFilenamesExported
            && !persistsScratchPaths
            && !scratchPathsExported
            && preservesExistingCounters
            && !customerDataExported
            && !diagnosticsOwnCleanup
    }
}

typealias C54EncryptedPortableEnvelopeDiagnosticStoreBoundaryV1 =
    C54EncryptedPortableEnvelopeDiagnosticsStoreBoundaryV1

// DIAGNOSTICS_SAME_ACTOR_AND_RAW_OWNER_HOOKS_V4_BEGIN
extension DiagnosticsStore {
    nonisolated func coldProducerLocationV4() -> (support: URL, directory: URL) {
        (applicationSupportURL, directoryURL) // SAME immutable sole actor fields, comparison DATA
    }
    nonisolated func coldProducerDateV4() -> Date { now() } // actual sole actor's selected clock
}

extension ColdDiagnosticsCheckedIOV1 {
    var diagnosticsProducerIsPerformingV4: Bool { state == .performing && frameEntered }
    /// Pure actual IO association, deliberately no issuer/current-owner
    /// callback and no scan while a real parent syscall has returned.
    func requireDiagnosticsRequestMechanicalAssociationV4(request: ColdEraseSchema2DiagnosticsRequestV1,
        issuer: ColdEraseDiagnosticsEffectIssuerV1) throws {
        guard (state == .registered || (state == .performing && frameEntered) || state == .checkedClosed),
              self.issuer === issuer, retainedIssuer == nil || retainedIssuer === issuer,
              !issuerReleased, issuerIdentity == ObjectIdentifier(issuer),
              operationID == issuer.operationID, diagnosticsIdentity == request.diagnosticsIdentity,
              mode == .replaceWithCanonicalZero, mode == request.mode,
              candidate.applicationSupportURL == request.applicationSupportURL,
              candidate.diagnosticsURL == request.diagnosticsURL,
              candidate.generatedAt == request.generatedAt,
              candidate.canonicalBytes == request.expectedCanonicalBytes,
              stack.count <= 3, resources.count <= 5, retiringResources.count <= 3,
              retiringEnumerations.count <= 2, retiringPolicyObservations.count <= 2,
              policyScopes.count <= 2, uncertainPolicyDescriptors.isEmpty,
              uncertainPolicyObservationScope == nil else { throw DiagnosticsFailure.invalidFile }
        for frame in stack {
            guard frame.intent.ioIdentity == ObjectIdentifier(self), frame.intent.operationID == operationID,
                  frame.outcome == nil || frame.outcome?.intent === frame.intent else { throw DiagnosticsFailure.invalidFile }
        }
        // Resources, cursor pointers, policy scope and returned raw outcomes
        // stay strongly retained by this SAME sole writer; no tuple is minted.
    }
    private struct ProducerStoredCellProfileV4 {
        let candidate: ColdDiagnosticsCandidateV1
        let issuer: ColdEraseDiagnosticsEffectIssuerV1?
        let retainedIssuer: ColdEraseDiagnosticsEffectIssuerV1?
        let issuerReleased: Bool
        let formatLease: NSRecursiveLock
        let issuerIdentity: ObjectIdentifier, diagnosticsIdentity: ObjectIdentifier
        let operationID: UUID
        let mode: Mode
        let state: State
        let frameEntered: Bool
        let sequence: UInt64
        let lastBoundary: String
        let stack: [Frame]
        let lastConsumedOutcome: ColdDiagnosticsPrimitiveOutcomeV1?
        let resources: [ColdDiagnosticsResourceV1], retiringResources: [ColdDiagnosticsResourceV1]
        let retiringEnumerations: [ColdDiagnosticsEnumerationAttemptV1]
        let directory: ColdDiagnosticsResourceV1?, temporary: ColdDiagnosticsResourceV1?
        let current: ColdDiagnosticsResourceV1?, observer: ColdDiagnosticsResourceV1?
        let enumeration: ColdDiagnosticsEnumerationAttemptV1?
        let policyScope: ColdDiagnosticsPolicyEffectScopeV1?
        let policyScopes: [ColdDiagnosticsPolicyEffectScopeV1]
        let policyObservationScope: ColdDiagnosticsPolicyObservationScopeV1?
        let retiringPolicyObservations: [ColdDiagnosticsPolicyObservationScopeV1]
        let uncertainPolicyObservationScope: ColdDiagnosticsPolicyObservationScopeV1?
        let uncertainPolicyDescriptors: [Int32]
        let acceptedDirectoryPolicy: TemporalPolicyObservationV1?, acceptedLeafPolicy: TemporalPolicyObservationV1?
        let receipt: ColdDiagnosticsCheckedReceiptV1?
        let completedPolicyReceiptValue: ColdDiagnosticsCompletedPolicyReceiptV1?
        let completedPolicyReceiptMinted: Bool
        let closedResourceCount: UInt64
        let closedResourceCensus: SHA256
        let finalClosedResourceCensusSHA256: String?
        let closedPolicyObservationCount: UInt64, closedPolicyObservationResourceCount: UInt64
        let closedPolicyObservationCensus: SHA256
        let finalPolicyObservationCensusSHA256: String?
        let currentImage: ColdDiagnosticsPhysicalImageV1?
    }
    private struct FrameProfileV4 {
        let intent: ColdDiagnosticsPrimitiveIntentV1
        let mutation: Bool
        let outcome: ColdDiagnosticsPrimitiveOutcomeV1?
        let proved: Bool
    }
    private struct IntentProfileV4 {
        let ioIdentity: ObjectIdentifier, operationID: UUID, sequence: UInt64
        let kind: ColdDiagnosticsPrimitiveIntentV1.Kind
        let before: ColdDiagnosticsPhysicalImageV1?
    }
    private struct OutcomeProfileV4 {
        let intent: ColdDiagnosticsPrimitiveIntentV1
        let result: ColdDiagnosticsPrimitiveResultV1
        let after: ColdDiagnosticsPhysicalImageV1?
    }
    private struct ReceiptProfileV4 {
        let ioIdentity: ObjectIdentifier, operationID: UUID
        let canonicalSHA256: String, byteCount: UInt64
        let currentImage: ColdDiagnosticsPhysicalImageV1
        let closedResourceIDs: [UUID], closedResourceCount: UInt64
        let closedResourceCensusSHA256: String
        let closedPolicyObservationCount: UInt64, closedPolicyObservationResourceCount: UInt64
        let closedPolicyObservationCensusSHA256: String
    }
    static var diagnosticsProducerStoredBackingV4: UInt64 {
        UInt64(MemoryLayout<ProducerStoredCellProfileV4>.stride
            + 3 * MemoryLayout<FrameProfileV4>.stride + 4 * MemoryLayout<IntentProfileV4>.stride
            + 4 * MemoryLayout<OutcomeProfileV4>.stride + MemoryLayout<ReceiptProfileV4>.stride
            + 5 * MemoryLayout<UUID>.stride + 24 * MemoryLayout<AnyObject?>.stride
            + 12 * MemoryLayout<ColdDiagnosticsPhysicalImageV1>.stride
            + 24 * MemoryLayout<ColdDiagnosticsPhysicalLeafV1>.stride
            + 12 * MemoryLayout<ColdDiagnosticsPolicyNodeV1.Ancestor>.stride + 16_384)
            + 5 * ColdDiagnosticsResourceV1.producerStoredBackingV4
            + 2 * ColdDiagnosticsPolicyEffectScopeV1.producerStoredBackingV4
            + 3 * ColdDiagnosticsPolicyObservationScopeV1.producerStoredBackingV4
            + 2 * ColdDiagnosticsEnumerationAttemptV1.producerStoredBackingV4
        // PFP's privately allocated attempt/resource graph and whole allocator
        // VM require their genuine enclosing profile; no reference stride
        // purports to measure those objects.
    }
}

extension ColdDiagnosticsResourceV1 {
    private struct ProducerProfileV4 {
        let id: UUID, role: Role, state: State
        let descriptor: Int32?, openedDescriptor: Int32?
        let directoryStream: UnsafeMutablePointer<DIR>?, fencedDirectoryStream: UnsafeMutablePointer<DIR>?
        let fact: EraseColdControlLeafFactV1?
        let closeResult: Int32?, closeErrno: Int32?
        let closedByIntent: ColdDiagnosticsPrimitiveIntentV1?
    }
    static var producerStoredBackingV4: UInt64 { UInt64(MemoryLayout<ProducerProfileV4>.stride) }
}
extension ColdDiagnosticsPolicyEffectScopeV1 {
    private struct ProducerProfileV4 {
        let state: State, io: ColdDiagnosticsCheckedIOV1?, uncertainIO: ColdDiagnosticsCheckedIOV1?
        let primitive: ColdDiagnosticsPrimitiveIntentV1, operationID: UUID, node: ColdDiagnosticsPolicyNodeV1
        let attempt: ColdDiagnosticsPolicyAttemptV1?
        let intents: [ColdDiagnosticsPolicySetterIntentV1], outcomes: [ColdDiagnosticsPolicySetterOutcomeV1]
        let uncertainDescriptors: [Int32], consumedIntent: ColdDiagnosticsPrimitiveIntentV1?
    }
    static var producerStoredBackingV4: UInt64 {
        UInt64(MemoryLayout<ProducerProfileV4>.stride + 16 * MemoryLayout<AnyObject?>.stride
            + 4 * MemoryLayout<Int32>.stride + 4 * MemoryLayout<ColdDiagnosticsPolicyNodeV1.Ancestor>.stride + 4_096)
    }
}
extension ColdDiagnosticsPolicyObservationScopeV1 {
    private struct ProducerProfileV4 {
        let state: State, io: ColdDiagnosticsCheckedIOV1?, uncertainIO: ColdDiagnosticsCheckedIOV1?
        let primitive: ColdDiagnosticsPrimitiveIntentV1, operationID: UUID, node: ColdDiagnosticsPolicyNodeV1
        let attempt: ColdDiagnosticsPolicyObservationAttemptV1?
        let consumedIntent: ColdDiagnosticsPrimitiveIntentV1?, uncertainDescriptors: [Int32]
    }
    static var producerStoredBackingV4: UInt64 {
        UInt64(MemoryLayout<ProducerProfileV4>.stride + 3 * MemoryLayout<Int32>.stride
            + 2 * MemoryLayout<ColdDiagnosticsPolicyNodeV1.Ancestor>.stride + 2_048)
    }
}
extension ColdDiagnosticsEnumerationAttemptV1 {
    private struct ProducerProfileV4 {
        let state: State, resource: ColdDiagnosticsResourceV1, ioIdentity: ObjectIdentifier, operationID: UUID
        let names: [String], reachedEOF: Bool, fdopendirErrno: Int32?, fdopendirReturn: UInt?
        let readdirErrnos: [Int32], actualReads: [ReadResult], closeResult: Int32?, closeErrno: Int32?
    }
    static var producerStoredBackingV4: UInt64 {
        UInt64(MemoryLayout<ProducerProfileV4>.stride + 5 * MemoryLayout<Int32>.stride
            + 5 * MemoryLayout<ReadResult>.stride + 2 * MemoryLayout<String>.stride + 128)
    }
}
// DIAGNOSTICS_SAME_ACTOR_AND_RAW_OWNER_HOOKS_V4_END


// DIAGNOSTICS_COMPLETED_CHECKED_CONTENT_RETIREMENT_V4_BEGIN
extension ColdDiagnosticsCheckedIOV1 {
    func requireHistoricalCheckedIssuerReleaseV4(issuer: ColdEraseDiagnosticsEffectIssuerV1,
        receipt: ColdDiagnosticsCheckedReceiptV1) throws {
        guard issuerReleased, self.issuer == nil, retainedIssuer == nil,
              issuerIdentity == ObjectIdentifier(issuer), self.receipt === receipt,
              receipt.ioIdentity == ObjectIdentifier(self), receipt.operationID == operationID,
              mode == .replaceWithCanonicalZero else { throw DiagnosticsFailure.invalidFile }
        try requireIssuerCheckedSettlement(receipt: receipt)
        // Actual positive once-closes and consumed policies remain owned by
        // this real checked IO. No released issuer or current scanner is called.
    }
}
// DIAGNOSTICS_COMPLETED_CHECKED_CONTENT_RETIREMENT_V4_END

// DIAGNOSTICS_GENUINE_TERMINAL_FORMAT_LEASE_CONSUMER_V4_BEGIN
extension ColdDiagnosticsCheckedIOV1 {
    fileprivate static var terminalActualCanonicalNamesV4: (directory: String, current: String) {
        (directoryName, currentName)
    }
    fileprivate static var terminalActualCanonicalNameBackingV4: UInt64 {
        UInt64(2 * MemoryLayout<String>.stride + directoryName.utf8.count + currentName.utf8.count)
        // Two actual temporary returned String references plus existing literal
        // UTF8 widths. Entry.Cells separately includes its retained two names.
    }
}

@MainActor final class ColdDiagnosticsTerminalFormatLeaseEntryV4 {
    private enum Phase { case active, returned, uncertain }
    private struct Cells {
        let request: ColdEraseSchema2TerminalDiagnosticsPolicyRequestV4
        let diagnostics: DiagnosticsStore
        let formatLease: NSRecursiveLock
        let directoryName: String
        let currentName: String
        let lockEntered: Bool
        var phase = Phase.active
        var firstError: Error?
        var receipt: ColdEraseSchema2TerminalDiagnosticsPolicyReceiptV4?
        var policyProofReturned = false
        var unlockEntered = false
        var unlockReturned = false
        var namesBorrowing = false
    }
    private var cells: Cells
    static var declaredBackingBytes: UInt64 {
        UInt64(MemoryLayout<Cells>.stride + MemoryLayout<Cells>.alignment - 1)
            + ColdDiagnosticsCheckedIOV1.terminalActualCanonicalNameBackingV4
        // Actual Native once-birth profile includes this BEFORE Entry birth.
        // Class header/Foundation/allocator/VM remain enclosing obligations.
    }
    private init(request: ColdEraseSchema2TerminalDiagnosticsPolicyRequestV4,
        diagnostics: DiagnosticsStore, formatLease: NSRecursiveLock,
        names: (directory: String, current: String)) {
        cells = .init(request: request, diagnostics: diagnostics, formatLease: formatLease,
            directoryName: names.directory, currentName: names.current, lockEntered: true)
    }
    /// Called only by the sole same-file DiagnosticsStore static helper after
    /// its actual admission and SAME static formatLease.lock() returned.
    fileprivate static func makeAfterActualStaticLockV4(
        request: ColdEraseSchema2TerminalDiagnosticsPolicyRequestV4,
        diagnostics: DiagnosticsStore, formatLease: NSRecursiveLock) -> ColdDiagnosticsTerminalFormatLeaseEntryV4 {
        .init(request: request, diagnostics: diagnostics, formatLease: formatLease,
            names: ColdDiagnosticsCheckedIOV1.terminalActualCanonicalNamesV4)
    }
    func requireActiveAssociationV4(request: ColdEraseSchema2TerminalDiagnosticsPolicyRequestV4) throws {
        guard cells.request === request, cells.lockEntered, cells.phase == .active,
              cells.firstError == nil, !cells.unlockEntered, !cells.unlockReturned,
              !cells.policyProofReturned else { throw DiagnosticsFailure.invalidFile }
        try request.requireConfiguredDiagnosticsIdentityV4(cells.diagnostics)
        // Pure same configured actor and entered private owner only. No current
        // resource proof or recursive Native Entry callback occurs here.
    }
    func retainActualFailureV4(request: ColdEraseSchema2TerminalDiagnosticsPolicyRequestV4, error: Error) {
        guard cells.request === request else { return }
        if cells.firstError == nil { cells.firstError = error }
        cells.phase = .uncertain
        // A reached names loan and all actual returned fields stay retained.
    }
    fileprivate func retainActualNativeReturnV4(_ receipt: ColdEraseSchema2TerminalDiagnosticsPolicyReceiptV4) {
        cells.receipt = receipt // actual returned object BEFORE any fallible postproof
    }
    fileprivate func recordActualPolicyProofReturnV4(
        _ receipt: ColdEraseSchema2TerminalDiagnosticsPolicyReceiptV4) throws {
        cells.policyProofReturned = true // actual Native callback Void return before secondary proof
        guard cells.phase == .active, cells.firstError == nil, cells.receipt === receipt,
              cells.lockEntered, !cells.unlockEntered, !cells.namesBorrowing else {
            throw DiagnosticsFailure.invalidFile
        }
        cells.phase = .returned
    }
    fileprivate func unlockActualStaticLeaseOnceV4() {
        guard cells.lockEntered, !cells.unlockEntered, !cells.unlockReturned else {
            let error = DiagnosticsFailure.invalidFile
            retainActualFailureV4(request: cells.request, error: error)
            cells.request.recordActualFormatLeaseFailureV4(entry: self, error: error)
            return // no retry or second unlock of the genuine static lease
        }
        cells.unlockEntered = true // one-way fence BEFORE actual nonthrowing unlock
        cells.formatLease.unlock()
        cells.unlockReturned = true // actual Void return, on success or retained uncertainty
    }
    func requireHistoricalReturnedAssociationV4(request: ColdEraseSchema2TerminalDiagnosticsPolicyRequestV4,
        receipt: ColdEraseSchema2TerminalDiagnosticsPolicyReceiptV4) throws {
        guard cells.request === request, cells.receipt === receipt,
              cells.phase == .returned, cells.firstError == nil, cells.policyProofReturned,
              cells.lockEntered, cells.unlockEntered, cells.unlockReturned,
              !cells.namesBorrowing else { throw DiagnosticsFailure.invalidFile }
        // Pure actual returned callback/unlock DATA after genuine control/root
        // closes. No live lock, Native/current/Control/Main/old pin callback.
    }
    func withActualCanonicalNamesV4(request: ColdEraseSchema2TerminalDiagnosticsPolicyRequestV4,
        _ body: (String, String) throws -> Void) throws {
        guard cells.request === request else { throw DiagnosticsFailure.invalidFile }
        do {
            guard !cells.namesBorrowing else { throw DiagnosticsFailure.invalidFile }
            try requireActiveAssociationV4(request: request)
            cells.namesBorrowing = true
            try body(cells.directoryName, cells.currentName)
            try requireActiveAssociationV4(request: request)
            cells.namesBorrowing = false
        } catch {
            retainActualFailureV4(request: request, error: error)
            request.recordActualFormatLeaseFailureV4(entry: self, error: error)
            throw error
        }
    }
}

extension DiagnosticsStore {
    @MainActor static func performColdTerminalCompletedPolicyV4(
        request: ColdEraseSchema2TerminalDiagnosticsPolicyRequestV4,
        diagnostics: DiagnosticsStore) throws -> ColdEraseSchema2TerminalDiagnosticsPolicyReceiptV4 {
        try request.requireConfiguredDiagnosticsIdentityV4(diagnostics)
        // Genuine once-paid Entry admission BEFORE any lock or constructor.
        // SAME-request recursion poisons its retained active Entry before a
        // recursive lock attempt or unpaid second object can be constructed.
        try request.beginActualFormatLeaseEntryBirthV4(diagnostics: diagnostics)
        Self.formatLease.lock()
        let entry = ColdDiagnosticsTerminalFormatLeaseEntryV4.makeAfterActualStaticLockV4(
            request: request, diagnostics: diagnostics, formatLease: Self.formatLease)
        defer { entry.unlockActualStaticLeaseOnceV4() }
        do {
            try request.retainActualFormatLeaseEntryV4(entry)
            let receipt = try request.performActualRootThenCurrentPolicyV4(entry: entry)
            entry.retainActualNativeReturnV4(receipt)
            try request.requireActualFormatLeasePolicyReturnV4(receipt, entry: entry)
            try entry.recordActualPolicyProofReturnV4(receipt)
            return receipt
        } catch {
            entry.retainActualFailureV4(request: request, error: error)
            request.recordActualFormatLeaseFailureV4(entry: entry, error: error)
            throw error
        }
    }
}
// DIAGNOSTICS_GENUINE_TERMINAL_FORMAT_LEASE_CONSUMER_V4_END

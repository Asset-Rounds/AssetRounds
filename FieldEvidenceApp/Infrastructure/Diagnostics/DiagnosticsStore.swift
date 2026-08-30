import Darwin
import Foundation

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

actor DiagnosticsStore: DeviceOperationalSupportStoreV2 {
    static let maximumOperationalRecordBytes =
        DeviceOperationalSupportStoreSchemaV2.maximumRecordBytes
    static let maximumOperationalTotalBytes =
        DeviceOperationalSupportStoreSchemaV2.maximumTotalBytes
    static let maximumOperationalRecords =
        DeviceOperationalSupportStoreSchemaV2.maximumRecords
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
        let linkCount: UInt64

        init(_ information: stat) throws {
            guard (information.st_mode & S_IFMT) == S_IFDIR else {
                throw DiagnosticsFailure.invalidFile
            }
            device = UInt64(information.st_dev)
            inode = UInt64(information.st_ino)
            linkCount = UInt64(information.st_nlink)
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
            if createIfMissing {
                try fileManager.createDirectory(
                    at: applicationSupportURL,
                    withIntermediateDirectories: true
                )
            }
            let applicationSupportDescriptor = Darwin.open(
                applicationSupportURL.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if applicationSupportDescriptor < 0 {
                if !createIfMissing, errno == ENOENT { return nil }
                throw DiagnosticsFailure.invalidFile
            }
            var ownsApplicationSupport = true
            defer {
                if ownsApplicationSupport {
                    _ = Darwin.close(applicationSupportDescriptor)
                }
            }
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
            guard !diagnosticsName.isEmpty,
                  diagnosticsURL.deletingLastPathComponent()
                    .standardizedFileURL == applicationSupportURL.standardizedFileURL else {
                throw DiagnosticsFailure.invalidFile
            }
            var diagnosticsDescriptor = Darwin.openat(
                applicationSupportDescriptor,
                diagnosticsName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if diagnosticsDescriptor < 0, errno == ENOENT {
                guard createIfMissing else { return nil }
                guard Darwin.mkdirat(
                    applicationSupportDescriptor,
                    diagnosticsName,
                    mode_t(0o700)
                ) == 0 || errno == EEXIST,
                      Darwin.fsync(applicationSupportDescriptor) == 0 else {
                    throw DiagnosticsFailure.invalidFile
                }
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
                guard persist(.zero) else { return }
                counters = .zero
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
                guard persist(.zero) else { return }
                counters = .zero
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
                isPrepared = true
                preparationFailure = nil
                if !isV2Envelope(data) {
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
            isPrepared = true
            preparationFailure = nil
            if !isV2Envelope(data) {
                guard persist(counters, health: decoded.health) else {
                    isPrepared = false
                    return
                }
            }
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            preparationFailure = .protectedDataUnavailable
            logger.record(.countersWriteFailed)
        } catch DiagnosticsFailure.unsupportedVersion {
            // A newer writer owns these bytes. Downgrade never destroys or
            // rewrites them; a compatible forward upgrade is required.
            preparationFailure = .unsupportedVersion
            logger.record(.countersWriteFailed)
        } catch {
            logger.record(.invalidCountersReset)
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
    }

    func operationalSupportSnapshot() async throws -> DeviceOperationalSupportSnapshotV2 {
        prepare()
        guard isPrepared, let health else {
            throw preparationFailure ?? DiagnosticsFailure.invalidFile
        }
        return try DeviceOperationalSupportSnapshotV2(health: health, counters: counters)
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
        health = candidate
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
        guard isPrepared else {
            throw preparationFailure ?? DiagnosticsFailure.invalidFile
        }
        let candidate = try emptyHealth()
        guard persist(.zero, health: candidate) else {
            throw DiagnosticsFailure.invalidFile
        }
        counters = .zero
        health = candidate
        isPrepared = true
        preparationFailure = nil
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
        repairExisting: Bool = false
    ) -> Bool {
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
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                at: directoryURL,
                authorityCheck: authorityCheck
            )
            let state = try DeviceOperationalSupportEnvelopeV2(
                health: try resolvedHealth(healthCandidate),
                counters: candidate
            )
            let data = try canonicalData(for: state)
            try C54EncryptedPortableEnvelopeDiagnosticPrivacyBoundaryV1.validate(
                data
            )
            guard data.count <= Self.maximumOperationalTotalBytes else {
                throw DiagnosticsFailure.sizeLimitExceeded
            }
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
            try syncFile(
                at: temporaryURL,
                expected: temporaryIdentity,
                authorityCheck: authorityCheck
            )
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
                    options: []
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
            try authorityCheck()
            replacementIdentity = try fileIdentity(
                at: countersURL,
                authorityCheck: authorityCheck
            )
            guard let replacementIdentity else {
                throw DiagnosticsFailure.invalidFile
            }
            try ProtectedFilePolicyV1.applyAndVerify(
                .diagnostics,
                at: countersURL,
                authorityCheck: authorityCheck
            )
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
            try syncDirectory(authorityCheck: authorityCheck)
            return true
        } catch {
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
            logger.record(.countersWriteFailed)
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
        guard let backupIdentity = try fileIdentityIfPresent(
            at: backupURL,
            authorityCheck: authorityCheck
        ) else {
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
                    _ = try decodeDiagnostics(data)
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
                _ = try decodeDiagnostics(data)
                try removeOwnedFile(
                    at: backupURL,
                    expected: backupIdentity,
                    authorityCheck: authorityCheck
                )
                try syncDirectory(authorityCheck: authorityCheck)
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                throw failure
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
                _ = try decodeDiagnostics(backupData)
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
            _ = try decodeDiagnostics(backupData)
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

    private func canonicalData<T: Encodable>(for value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func decodeOperationalStore(
        _ data: Data
    ) throws -> DeviceOperationalSupportEnvelopeV2 {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            if let dictionary = object as? [String: Any],
               let version = dictionary["schemaVersion"] as? NSNumber,
               version.intValue > DeviceOperationalSupportStoreSchemaV2.version {
                throw DiagnosticsFailure.unsupportedVersion
            }
        } catch DiagnosticsFailure.unsupportedVersion {
            throw DiagnosticsFailure.unsupportedVersion
        } catch {
            // Canonical decoding below owns the visible corruption outcome.
        }
        do {
            let value = try JSONDecoder().decode(
                DeviceOperationalSupportEnvelopeV2.self,
                from: data
            )
            try value.validate()
            guard try canonicalData(for: value) == data,
                  data.count <= Self.maximumOperationalTotalBytes else {
                throw DiagnosticsFailure.invalidFile
            }
            return value
        } catch DiagnosticsFailure.invalidFile {
            throw DiagnosticsFailure.invalidFile
        } catch {
            // A released DiagnosticsV1 document is the sole older format.
        }
        let legacy = try JSONDecoder().decode(DiagnosticsV1.self, from: data)
        guard legacy.isValid, try canonicalData(for: legacy) == data else {
            throw DiagnosticsFailure.invalidFile
        }
        let migrated = try DeviceOperationalSupportEnvelopeV2(
            health: try emptyHealth(),
            counters: legacy
        )
        return migrated
    }

    private func isV2Envelope(_ data: Data) -> Bool {
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
        return version.intValue == DeviceOperationalSupportEnvelopeV2.schemaVersion
            && dictionary["health"] != nil
            && dictionary["counters"] != nil
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

    private static func makeEmptyHealth(
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
}

private enum DiagnosticsFailure: Error {
    case invalidFile
    case protectedDataUnavailable
    case sizeLimitExceeded
    case unsupportedVersion
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

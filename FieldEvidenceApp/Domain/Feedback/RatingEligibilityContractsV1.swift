import Foundation

enum RatingEligibilityFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, invalidCandidate, staleState
    case divergentReplay, storageUnavailable, automaticRequestDisabled
}

struct RatingEligibilityPolicyV1: Codable, Equatable, Sendable {
    static let minimumDistinctSeries = 3
    static let minimumSeriesSpanSeconds: TimeInterval = 7 * 86_400
    static let minimumAttemptIntervalSeconds: TimeInterval = 120 * 86_400
    static let rollingYearSeconds: TimeInterval = 365 * 86_400
    static let maximumAttemptsPerRollingYear = 2
    static let eraseCooldownSeconds: TimeInterval = 365 * 86_400

    let minimumDistinctSeries: Int
    let minimumSeriesSpanSeconds: TimeInterval
    let minimumAttemptIntervalSeconds: TimeInterval
    let rollingYearSeconds: TimeInterval
    let maximumAttemptsPerRollingYear: Int
    let eraseCooldownSeconds: TimeInterval

    init() {
        minimumDistinctSeries = Self.minimumDistinctSeries
        minimumSeriesSpanSeconds = Self.minimumSeriesSpanSeconds
        minimumAttemptIntervalSeconds = Self.minimumAttemptIntervalSeconds
        rollingYearSeconds = Self.rollingYearSeconds
        maximumAttemptsPerRollingYear = Self.maximumAttemptsPerRollingYear
        eraseCooldownSeconds = Self.eraseCooldownSeconds
    }

    func validate() throws {
        guard minimumDistinctSeries == Self.minimumDistinctSeries,
              minimumSeriesSpanSeconds == Self.minimumSeriesSpanSeconds,
              minimumAttemptIntervalSeconds == Self.minimumAttemptIntervalSeconds,
              rollingYearSeconds == Self.rollingYearSeconds,
              maximumAttemptsPerRollingYear == Self.maximumAttemptsPerRollingYear,
              eraseCooldownSeconds == Self.eraseCooldownSeconds else {
            throw RatingEligibilityFailureV1.invalidValue
        }
    }

    var policySHA256: String { get throws { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) } }
}

struct RatingMarketingVersionV1: Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty, rawValue.utf8.count <= 32,
              (1...4).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        self.rawValue = rawValue
    }
}

struct RatingBuildVersionV1: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
    init(_ rawValue: String) throws {
        guard !rawValue.isEmpty, rawValue.utf8.count <= 32,
              rawValue.allSatisfy(\.isNumber) else { throw RatingEligibilityFailureV1.invalidValue }
        self.rawValue = rawValue
    }
}

enum RatingCompletedActivitySnapshotEvidenceV1: Equatable, Sendable {
    case v1(CompletedActivitySnapshotV1)
    case v2(CompletedActivitySnapshotV2)

    var activity: CompletedActivitySnapshotPayloadV1 {
        switch self {
        case .v1(let snapshot): return snapshot.payload
        case .v2(let snapshot): return snapshot.payload.activity
        }
    }

    var snapshotSHA256: String {
        switch self {
        case .v1(let snapshot): return snapshot.snapshotSHA256
        case .v2(let snapshot): return snapshot.snapshotSHA256
        }
    }

    func validate() throws {
        switch self {
        case .v1(let snapshot): try snapshot.validate()
        case .v2(let snapshot): try snapshot.validate()
        }
    }
}

struct RatingFinalizedActivityCandidateV1: Sendable {
    let envelope: MutationEnvelopeV1
    let receipt: MutationReceiptV1
    let record: WorkflowRecordPayloadV1
    let packet: PacketPayloadV1
    let report: ReportPayloadV1
    let completedSnapshot: RatingCompletedActivitySnapshotEvidenceV1
    let practiceProvenance: PracticeWorkspaceProvenanceV1?

    init(envelope: MutationEnvelopeV1, receipt: MutationReceiptV1,
         record: WorkflowRecordPayloadV1, packet: PacketPayloadV1,
         report: ReportPayloadV1,
         completedSnapshot: RatingCompletedActivitySnapshotEvidenceV1,
         practiceProvenance: PracticeWorkspaceProvenanceV1?) {
        self.envelope = envelope; self.receipt = receipt; self.record = record
        self.packet = packet; self.report = report; self.completedSnapshot = completedSnapshot
        self.practiceProvenance = practiceProvenance
    }

    init(envelope: MutationEnvelopeV1, receipt: MutationReceiptV1,
         record: WorkflowRecordPayloadV1, packet: PacketPayloadV1,
         report: ReportPayloadV1, completedSnapshot: CompletedActivitySnapshotV1,
         practiceProvenance: PracticeWorkspaceProvenanceV1?) {
        self.init(envelope: envelope, receipt: receipt, record: record, packet: packet,
                  report: report, completedSnapshot: .v1(completedSnapshot),
                  practiceProvenance: practiceProvenance)
    }

    init(envelope: MutationEnvelopeV1, receipt: MutationReceiptV1,
         record: WorkflowRecordPayloadV1, packet: PacketPayloadV1,
         report: ReportPayloadV1, completedSnapshot: CompletedActivitySnapshotV2,
         practiceProvenance: PracticeWorkspaceProvenanceV1?) {
        self.init(envelope: envelope, receipt: receipt, record: record, packet: packet,
                  report: report, completedSnapshot: .v2(completedSnapshot),
                  practiceProvenance: practiceProvenance)
    }
}

/// Runtime-only proof. It may contain work identities because it is never
/// encoded or admitted to the device-local rating ledger.
struct RatingEligibleCompletionProjectionV1: Equatable, Sendable {
    let finalizationMutationID: MutationIDV1
    let activitySeriesID: UUID
    let completedAt: Date
    let snapshotSHA256: String

    init(candidate: RatingFinalizedActivityCandidateV1) throws {
        try candidate.envelope.validate(); try candidate.receipt.validate()
        try candidate.completedSnapshot.validate(); try candidate.practiceProvenance?.validate()
        let completedActivity = candidate.completedSnapshot.activity
        guard candidate.practiceProvenance == nil,
              candidate.receipt.envelopeSHA256 == (try candidate.envelope.canonicalSHA256()),
              candidate.receipt.commandBodySHA256 == candidate.envelope.commandBodySHA256,
              candidate.receipt.mutationID == candidate.envelope.mutationID,
              candidate.receipt.identity.workspaceID == candidate.envelope.workspaceID,
              candidate.receipt.sourceKind == .localUser,
              case .finalizeCheck(let command) = candidate.envelope.command,
              command.finalizationMutationID == candidate.envelope.mutationID.rawValue,
              command.recordID == candidate.record.id,
              command.packetID == candidate.packet.id,
              command.reportID == candidate.report.id,
              candidate.record.state == WorkflowState.completed.rawValue,
              candidate.record.revisionKind == WorkflowRevisionKind.original.rawValue,
              candidate.record.packetID == candidate.packet.id,
              candidate.packet.evaluationCounted,
              candidate.packet.currentRecordID == candidate.record.id,
              candidate.report.packetID == candidate.packet.id,
              candidate.report.sourceRecordID == candidate.record.id,
              candidate.report.snapshotSHA256 == candidate.completedSnapshot.snapshotSHA256,
              completedActivity.snapshotRevision == 1,
              completedActivity.supersedesSnapshotID == nil,
              completedActivity.supersededSnapshotSHA256 == nil,
              completedActivity.reportID == candidate.report.id.uuidString.lowercased(),
              completedActivity.sourceActivityID == candidate.record.id.uuidString.lowercased(),
              let date = Self.instant(completedActivity.completedAt),
              candidate.record.completedAt == date else {
            throw RatingEligibilityFailureV1.invalidCandidate
        }
        finalizationMutationID = candidate.envelope.mutationID
        activitySeriesID = candidate.packet.stableRootID
        completedAt = date
        snapshotSHA256 = candidate.completedSnapshot.snapshotSHA256
    }

    private static func instant(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

enum RatingActiveContextV1: String, Codable, CaseIterable, Hashable, Sendable {
    case error = "ERROR", recovery = "RECOVERY", purchase = "PURCHASE"
    case permission = "PERMISSION", importFlow = "IMPORT", exportOrShare = "EXPORT_OR_SHARE"
    case capture = "CAPTURE", destructiveConfirmation = "DESTRUCTIVE_CONFIRMATION"
    case activeWork = "ACTIVE_WORK"
}

struct RatingNaturalStopV1: Equatable, Sendable {
    let eventID: UUID
    let successfullyRetrievedSnapshotSHA256: String
    let occurredAt: Date
    let isLaterVoluntaryReopen: Bool
    let activeContexts: Set<RatingActiveContextV1>
    let activeSceneAvailable: Bool

    func validate() throws {
        guard eventID != UUID.zero,
              KernelCanonicalHashV1.validSHA256(successfullyRetrievedSnapshotSHA256),
              occurredAt.timeIntervalSinceReferenceDate.isFinite else {
            throw RatingEligibilityFailureV1.invalidValue
        }
    }
}

enum RatingEligibilityReasonV1: String, Codable, CaseIterable, Comparable, Sendable {
    case insufficientDistinctSeries = "INSUFFICIENT_DISTINCT_SERIES"
    case insufficientSevenDaySpan = "INSUFFICIENT_SEVEN_DAY_SPAN"
    case alreadyAttemptedForVersion = "ALREADY_ATTEMPTED_FOR_VERSION"
    case withinOneHundredTwentyDayCooldown = "WITHIN_120_DAY_COOLDOWN"
    case rollingYearAttemptLimit = "ROLLING_YEAR_ATTEMPT_LIMIT"
    case erasedInstallationCooldown = "ERASED_INSTALLATION_COOLDOWN"
    case clockRollbackDetected = "CLOCK_ROLLBACK_DETECTED"
    case invalidMarketingVersion = "INVALID_MARKETING_VERSION"
    case noNaturalIdleStop = "NO_NATURAL_IDLE_STOP"
    case sceneUnavailable = "SCENE_UNAVAILABLE"
    case activeContext = "ACTIVE_CONTEXT"
    case ledgerCorrupt = "LEDGER_CORRUPT"
    case ledgerFutureVersion = "LEDGER_FUTURE_VERSION"
    case ledgerMigrationFailed = "LEDGER_MIGRATION_FAILED"
    case ledgerUnavailable = "LEDGER_UNAVAILABLE"
    case automaticRequestDisabledUnverifiedPlatform = "AUTOMATIC_REQUEST_DISABLED_UNVERIFIED_PLATFORM"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum RatingLedgerOriginV1: Codable, Equatable, Sendable {
    case established
    case erasedCooldown(erasedAt: Date, suppressUntil: Date)
}

enum RatingAttemptDispositionV1: String, Codable, Sendable {
    case reservedBeforeNativeCall = "RESERVED_BEFORE_NATIVE_CALL"
    case nativeRequestInvoked = "NATIVE_REQUEST_INVOKED"
}

struct RatingRequestAttemptV1: Codable, Equatable, Sendable {
    /// Opaque, nonreversible operation-deduplication digest. It is not a
    /// customer, workspace, work, activity, snapshot, receipt, or event identity.
    let idempotencyKeySHA256: String
    let policySHA256: String
    let marketingVersion: RatingMarketingVersionV1
    let buildVersion: RatingBuildVersionV1
    let reservedAt: Date
    let nativeInvokedAt: Date?
    let disposition: RatingAttemptDispositionV1

    func validate() throws {
        guard (try? RatingMarketingVersionV1(marketingVersion.rawValue)) == marketingVersion,
              (try? RatingBuildVersionV1(buildVersion.rawValue)) == buildVersion else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        guard KernelCanonicalHashV1.validSHA256(idempotencyKeySHA256),
              KernelCanonicalHashV1.validSHA256(policySHA256),
              reservedAt.timeIntervalSinceReferenceDate.isFinite,
              nativeInvokedAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              (disposition == .nativeRequestInvoked) == (nativeInvokedAt != nil),
              nativeInvokedAt.map({ $0 >= reservedAt }) ?? true else {
            throw RatingEligibilityFailureV1.invalidValue
        }
    }
}

struct RatingRequestAttemptLedgerStateV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumAttempts = 256
    let schemaVersion: Int
    let revision: UInt64
    let origin: RatingLedgerOriginV1
    let attempts: [RatingRequestAttemptV1]
    let clockHighWatermarkUTC: Date
    let stateSHA256: String

    init(revision: UInt64, origin: RatingLedgerOriginV1,
         attempts: [RatingRequestAttemptV1], clockHighWatermarkUTC: Date) throws {
        schemaVersion = Self.schemaVersion; self.revision = revision; self.origin = origin
        self.attempts = attempts.sorted { ($0.reservedAt, $0.idempotencyKeySHA256) < ($1.reservedAt, $1.idempotencyKeySHA256) }
        self.clockHighWatermarkUTC = clockHighWatermarkUTC
        stateSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            revision: revision, origin: origin, attempts: self.attempts,
            clockHighWatermarkUTC: clockHighWatermarkUTC))
        try validate()
    }

    func validate() throws {
        try attempts.forEach { try $0.validate() }
        switch origin {
        case .established: break
        case .erasedCooldown(let erasedAt, let suppressUntil):
            guard erasedAt.timeIntervalSinceReferenceDate.isFinite,
                  suppressUntil.timeIntervalSinceReferenceDate.isFinite,
                  suppressUntil.timeIntervalSince(erasedAt) == RatingEligibilityPolicyV1.eraseCooldownSeconds,
                  attempts.isEmpty else { throw RatingEligibilityFailureV1.invalidValue }
        }
        guard schemaVersion == Self.schemaVersion, revision > 0,
              attempts.count <= Self.maximumAttempts,
              Set(attempts.map(\.idempotencyKeySHA256)).count == attempts.count,
              attempts == attempts.sorted(by: {
                ($0.reservedAt, $0.idempotencyKeySHA256) < ($1.reservedAt, $1.idempotencyKeySHA256)
              }),
              clockHighWatermarkUTC.timeIntervalSinceReferenceDate.isFinite,
              stateSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion,
                revision: revision, origin: origin, attempts: attempts,
                clockHighWatermarkUTC: clockHighWatermarkUTC))) else {
            throw RatingEligibilityFailureV1.invalidDigest
        }
    }
    private struct Basis: Codable { let schemaVersion: Int; let revision: UInt64
        let origin: RatingLedgerOriginV1; let attempts: [RatingRequestAttemptV1]
        let clockHighWatermarkUTC: Date }
}

enum RatingLedgerLoadResultV1: Sendable {
    case absentFreshInstall
    case current(RatingRequestAttemptLedgerStateV1)
    case corrupt, futureVersion, migrationFailed
}

enum RatingLedgerPersistenceDispositionV1: String, Codable, Sendable {
    case committed = "COMMITTED", idempotentReplay = "IDEMPOTENT_REPLAY"
}

struct RatingLedgerPersistenceReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let expectedRevision: UInt64?
    let resultingRevision: UInt64
    let stateSHA256: String
    let disposition: RatingLedgerPersistenceDispositionV1
}

protocol RatingEligibilityStoreV1: Sendable {
    func load() async throws -> RatingLedgerLoadResultV1
    func compareAndSwap(operationID: UUID, expectedRevision: UInt64?,
                        successor: RatingRequestAttemptLedgerStateV1) async throws
        -> RatingLedgerPersistenceReceiptV1
}

enum RatingNativeRequestAvailabilityV1: String, Sendable {
    case available = "AVAILABLE"
    case sceneUnavailable = "SCENE_UNAVAILABLE"
    case disabledUnverifiedPlatform = "DISABLED_UNVERIFIED_PLATFORM"
}

enum RatingNativeRequestResultV1: String, Sendable {
    case systemConsiderationRequested = "SYSTEM_CONSIDERATION_REQUESTED"
}

/// Captures the exact verified scene-bound native request before persistence.
/// UIKit remains owned by the adapter; this domain capability is nonthrowing.
@MainActor struct RatingNativeRequestPreparationV1 {
    private let invocation: @MainActor () -> RatingNativeRequestResultV1

    init(invocation: @escaping @MainActor () -> RatingNativeRequestResultV1) {
        self.invocation = invocation
    }

    func invoke() -> RatingNativeRequestResultV1 { invocation() }
}

@MainActor protocol RatingRequestAdapterV1: AnyObject {
    var availability: RatingNativeRequestAvailabilityV1 { get }
    func prepareRequest() -> RatingNativeRequestPreparationV1?
}

enum RateAppLinkV1: Equatable, Sendable {
    case available(URL)
    case disabledUnverifiedAppStoreID(TypedAvailabilityAndFallbackReceiptV1)

    static func available(appStoreID: String) throws -> Self {
        guard !appStoreID.isEmpty, appStoreID.allSatisfy(\.isNumber),
              let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        return .available(url)
    }
}

struct RatingEligibilityProjectionV1: Equatable, Sendable {
    let eligible: Bool
    let reasons: [RatingEligibilityReasonV1]
    let distinctSeriesCount: Int
    let observedSeriesSpanSeconds: TimeInterval
    let supportVisible: Bool
    let recoveryVisible: Bool
}

enum RatingCompletionRecordingOutcomeV1: Equatable, Sendable {
    case eligibleRuntimeProjection(RatingEligibleCompletionProjectionV1)
    case excluded
}

enum RatingRequestOutcomeV1: Equatable, Sendable {
    case ineligible(RatingEligibilityProjectionV1)
    case duplicateConservativeAttempt(RatingRequestAttemptV1)
    case nativeRequestInvoked(RatingRequestAttemptV1)
    case nativeRequestInvokedStatusPersistencePending(RatingRequestAttemptV1)
}

enum RatingResetOutcomeV1: String, Sendable { case preserved = "PRESERVED" }

struct RatingEraseOutcomeV1: Equatable, Sendable {
    let receipt: RatingLedgerPersistenceReceiptV1
    let suppressUntil: Date
}

enum RatingEligibilityPrivacyBoundaryV1 {
    static let persistedWorkspaceIDs = false
    static let persistedActivitySeriesIDs = false
    static let persistedReceiptSnapshotOrReportIDs = false
    static let includedInWorkspaceBackupExportSearchOrDiagnostics = false
    static let eraseCooldownContainsCustomerData = false
    static let telemetryOrMarketingWrites = false
}

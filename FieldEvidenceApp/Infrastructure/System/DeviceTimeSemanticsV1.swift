import Foundation

enum ScheduleDeviceClockBoundaryV1 {
    static let wallClockRollbackMutatesOccurrenceHistory = false
    static func validateEvaluationInstant(_ value: Date) throws { try ScheduleLimitsV1.instant(value) }
}

enum DeviceTimeSemanticsFailureV1: Error, Equatable, Sendable {
    case invalidWallTime
    case monotonicClockRegressed
    case durationOverflow
}

/// Durable wall-time context for display and historic evidence. Causal order
/// belongs to revisions/receipts, never this record.
struct DeviceWallTimeRecordV1: Codable, Equatable, Sendable {
    static let maximumTimeZoneIdentifierUTF8ByteCount = 255
    static let maximumAbsoluteUTCOffsetSeconds = 18 * 60 * 60

    let recordedAtUTC: Date
    let timeZoneIdentifier: String
    let utcOffsetSeconds: Int
    let isDaylightSavingTime: Bool

    func validate() throws {
        let scalars = timeZoneIdentifier.unicodeScalars
        let validOffsetRange = -Self.maximumAbsoluteUTCOffsetSeconds...
            Self.maximumAbsoluteUTCOffsetSeconds
        guard recordedAtUTC.timeIntervalSinceReferenceDate.isFinite,
              !timeZoneIdentifier.isEmpty,
              timeZoneIdentifier == timeZoneIdentifier.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              timeZoneIdentifier.utf8.count
                <= Self.maximumTimeZoneIdentifierUTF8ByteCount,
              scalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }),
              validOffsetRange.contains(utcOffsetSeconds) else {
            throw DeviceTimeSemanticsFailureV1.invalidWallTime
        }
    }
}

/// Process-local duration token. It cannot be encoded or restored.
struct InProcessDurationTokenV1: Equatable, Sendable {
    fileprivate let startedAt: ApplicationMonotonicInstantV1
}

struct DeviceTimeSemanticsV1: Sendable {
    private let wallClock: any ApplicationClock
    private let monotonicClock: any ApplicationMonotonicClockV1

    init(
        wallClock: any ApplicationClock = SystemApplicationClock(),
        monotonicClock: any ApplicationMonotonicClockV1 =
            SystemApplicationMonotonicClockV1()
    ) {
        self.wallClock = wallClock
        self.monotonicClock = monotonicClock
    }

    func wallTimeRecord(
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> DeviceWallTimeRecordV1 {
        let instant = wallClock.now()
        let offset = timeZone.secondsFromGMT(for: instant)
        let daylightSaving = timeZone.isDaylightSavingTime(for: instant)
        let record = DeviceWallTimeRecordV1(
            recordedAtUTC: instant,
            timeZoneIdentifier: timeZone.identifier,
            utcOffsetSeconds: offset,
            isDaylightSavingTime: daylightSaving
        )
        try record.validate()
        guard record.utcOffsetSeconds == offset,
              record.isDaylightSavingTime == daylightSaving else {
            throw DeviceTimeSemanticsFailureV1.invalidWallTime
        }
        return record
    }

    func beginDuration() -> InProcessDurationTokenV1 {
        InProcessDurationTokenV1(startedAt: monotonicClock.instant())
    }

    func elapsed(
        since token: InProcessDurationTokenV1
    ) throws -> Duration {
        let endedAt = monotonicClock.instant()
        guard endedAt >= token.startedAt else {
            throw DeviceTimeSemanticsFailureV1.monotonicClockRegressed
        }
        let delta = endedAt.uptimeNanoseconds
            - token.startedAt.uptimeNanoseconds
        guard delta <= UInt64(Int64.max) else {
            throw DeviceTimeSemanticsFailureV1.durationOverflow
        }
        return .nanoseconds(Int64(delta))
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_System_DeviceTimeSemanticsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_System_DeviceTimeSemanticsV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_System_DeviceTimeSemanticsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/System/DeviceTimeSemanticsV1.swift", role: .evidence)
}

enum C31LightingDeviceTimeBoundaryV1 {
    static let deviceClockIsEvidenceContextOnly = true
    static let clockValueDoesNotClassifyLightingCondition = true
    static let historicDisplayPreservesRecordedTime = true
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_System_DeviceTimeSemanticsV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

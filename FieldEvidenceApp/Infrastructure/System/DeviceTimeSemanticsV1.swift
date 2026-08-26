import Foundation

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

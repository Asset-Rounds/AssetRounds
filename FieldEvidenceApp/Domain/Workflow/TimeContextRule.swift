import Foundation

struct FrozenTimeContext: Equatable, Sendable {
    let observedAtUTC: Date
    let timeZoneID: String
    let utcOffsetMinutes: Int
    let localDate: String
    let localTime: String
}

enum TimeContextRuleError: Error, Equatable {
    case invalidTimeZoneID
}

enum TimeContextRule {
    static func freeze(
        observedAtUTC: Date,
        confirmedTimeZoneID: String
    ) throws -> FrozenTimeContext {
        guard TimeZone.knownTimeZoneIdentifiers.contains(confirmedTimeZoneID),
              let timeZone = TimeZone(identifier: confirmedTimeZoneID) else {
            throw TimeContextRuleError.invalidTimeZoneID
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm:ss"

        return FrozenTimeContext(
            observedAtUTC: observedAtUTC,
            timeZoneID: confirmedTimeZoneID,
            utcOffsetMinutes: timeZone.secondsFromGMT(for: observedAtUTC) / 60,
            localDate: dateFormatter.string(from: observedAtUTC),
            localTime: timeFormatter.string(from: observedAtUTC)
        )
    }
}

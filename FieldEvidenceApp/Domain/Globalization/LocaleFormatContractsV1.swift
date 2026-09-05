import Foundation

/// Fail-closed outcomes for locale presentation. None of these values may be
/// substituted into canonical storage, identifiers, or authored evidence.
enum LocaleFormattingFailureV1: Error, Equatable, Sendable {
    case invalidGregorianDate
    case invalidWallTime
    case nonexistentDSTTime
    case ambiguousDSTTimeRequiresChoice
    case invalidLocalizedInput
    case lossyLocalizedRoundTrip
    case unsupportedCurrencyCode
    case invalidAddressPresentation
    case invalidPhonePresentation
}

/// A calendar-neutral civil day kept in the Gregorian calendar for canonical
/// storage. Its display calendar is selected separately by the formatter.
struct LocaleGregorianDateV1: Codable, Equatable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard (1...9999).contains(year),
              let value = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: value) ==
                DateComponents(year: year, month: month, day: day) else {
            throw LocaleFormattingFailureV1.invalidGregorianDate
        }
        self.year = year
        self.month = month
        self.day = day
    }

    private enum CodingKeys: String, CodingKey { case year, month, day }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            year: container.decode(Int.self, forKey: .year),
            month: container.decode(Int.self, forKey: .month),
            day: container.decode(Int.self, forKey: .day)
        )
    }

    var canonicalString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

struct LocaleWallTimeV1: Codable, Equatable, Hashable, Sendable {
    let hour: Int
    let minute: Int
    let second: Int

    init(hour: Int, minute: Int, second: Int = 0) throws {
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            throw LocaleFormattingFailureV1.invalidWallTime
        }
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    private enum CodingKeys: String, CodingKey { case hour, minute, second }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hour: container.decode(Int.self, forKey: .hour),
            minute: container.decode(Int.self, forKey: .minute),
            second: container.decode(Int.self, forKey: .second)
        )
    }
}

/// Repeated local wall times require an explicit caller choice. A normal time
/// does not use this choice; a nonexistent time is always rejected.
enum LocaleDSTDisambiguationV1: String, Codable, Equatable, Sendable {
    case requireExplicit = "REQUIRE_EXPLICIT"
    case earlier = "EARLIER"
    case later = "LATER"
}

struct LocaleWeekRulesV1: Codable, Equatable, Sendable {
    let firstWeekday: Int
    let minimumDaysInFirstWeek: Int
}

enum LocalePaperSizeV1: String, Codable, CaseIterable, Sendable {
    case usLetter = "US_LETTER"
    case a4 = "A4"
}

struct LocalePaperLayoutV1: Codable, Equatable, Sendable {
    let paperSize: LocalePaperSizeV1
    let widthPoints: Double
    let heightPoints: Double
}

enum LocaleLengthUnitV1: String, Codable, CaseIterable, Sendable {
    case meters = "METERS"
    case feet = "FEET"
}

struct LocaleCurrencyAmountV1: Codable, Equatable, Sendable {
    let amount: Decimal
    let currencyCode: String

    init(amount: Decimal, currencyCode: String) throws {
        let uppercase = currencyCode.uppercased()
        guard !amount.isNaN,
              uppercase.count == 3,
              uppercase.allSatisfy({ $0.isASCII && $0.isLetter }),
              Locale.commonISOCurrencyCodes.contains(uppercase) else {
            throw LocaleFormattingFailureV1.unsupportedCurrencyCode
        }
        self.amount = amount
        self.currencyCode = uppercase
    }

    private enum CodingKeys: String, CodingKey { case amount, currencyCode }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            amount: container.decode(Decimal.self, forKey: .amount),
            currencyCode: container.decode(String.self, forKey: .currencyCode)
        )
    }
}

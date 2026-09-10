import Foundation

/// Foundation-backed presentation boundary. It formats canonical values for a
/// supplied profile; callers must retain the original values, units, and IANA
/// zone rather than storing any returned display string.
struct LocaleFormattingServiceV1 {
    enum DateStyleV1: Sendable { case short, medium, long }
    enum TimeStyleV1: Sendable { case short, medium }

    let profile: FormattingLocaleProfileV1
    private let resolvedTimeZone: TimeZone

    init(profile: FormattingLocaleProfileV1) throws {
        let validated = try FormattingLocaleProfileV1(
            localeIdentifier: profile.localeIdentifier,
            ianaTimeZoneIdentifier: profile.ianaTimeZoneIdentifier,
            calendar: profile.calendar,
            numberingSystem: profile.numberingSystem,
            units: profile.units
        )
        guard let timeZone = TimeZone(identifier: validated.ianaTimeZoneIdentifier) else {
            throw GlobalizationAxisFailureV1.invalidTimeZone
        }
        self.profile = validated
        resolvedTimeZone = timeZone
    }

    func displayGregorianDate(_ value: LocaleGregorianDateV1, style: DateStyleV1 = .medium) -> String {
        guard let anchor = gregorianDisplayAnchor(value) else { return value.canonicalString }
        return civilDateFormatter(style: style).string(from: anchor)
    }

    /// Only a nonnumeric, locale-produced date is accepted for interactive
    /// input. Numeric dates are ambiguous in destructive or report-critical
    /// flows; canonical `yyyy-MM-dd` uses `decodeCanonicalGregorianDate`.
    func parseDisplayedGregorianDate(_ value: String) throws -> LocaleGregorianDateV1 {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !isASCIIOnlyNumericDate(value) else {
            throw LocaleFormattingFailureV1.invalidLocalizedInput
        }
        let formatter = civilDateFormatter(style: .medium)
        guard let date = formatter.date(from: value) else {
            throw LocaleFormattingFailureV1.invalidLocalizedInput
        }
        let components = utcGregorianCalendar.dateComponents(in: .gmt, from: date)
        let parsed = try LocaleGregorianDateV1(
            year: try required(components.year), month: try required(components.month), day: try required(components.day)
        )
        guard displayGregorianDate(parsed, style: .medium) == value else {
            throw LocaleFormattingFailureV1.lossyLocalizedRoundTrip
        }
        return parsed
    }

    func displayInstant(
        _ value: Date,
        dateStyle: DateStyleV1 = .medium,
        timeStyle: TimeStyleV1 = .short
    ) -> String {
        dateFormatter(dateStyle: dateStyle, timeStyle: timeStyle).string(from: value)
    }

    func displayWallTime(_ value: LocaleWallTimeV1) throws -> String {
        try Self.displayCanonicalLocalTime(value.canonicalString, locale: locale)
    }

    /// Parsing a wall clock never assigns today's date or guesses an instant.
    /// A 12-hour locale requires the locale's complete AM/PM representation.
    func parseDisplayedWallTime(_ value: String) throws -> LocaleWallTimeV1 {
        let formatter = Self.wallTimeFormatter(locale: locale)
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, let date = formatter.date(from: value) else {
            throw LocaleFormattingFailureV1.invalidLocalizedInput
        }
        let parts = utcGregorianCalendar.dateComponents([.hour, .minute, .second], from: date)
        guard let hour = parts.hour, let minute = parts.minute, let second = parts.second else {
            throw LocaleFormattingFailureV1.invalidWallTime
        }
        let wall = try LocaleWallTimeV1(hour: hour, minute: minute, second: second)
        guard try displayWallTime(wall) == value else {
            throw LocaleFormattingFailureV1.lossyLocalizedRoundTrip
        }
        return wall
    }

    func resolveInstant(
        localDate: LocaleGregorianDateV1,
        localTime: LocaleWallTimeV1,
        disambiguation: LocaleDSTDisambiguationV1 = .requireExplicit
    ) throws -> Date {
        guard let start = gregorianCalendar.date(from: DateComponents(
            timeZone: timeZone, year: localDate.year, month: localDate.month, day: localDate.day, hour: 0
        )) else {
            throw LocaleFormattingFailureV1.invalidGregorianDate
        }
        let matching = DateComponents(hour: localTime.hour, minute: localTime.minute, second: localTime.second)
        let earlier = gregorianCalendar.nextDate(
            after: start.addingTimeInterval(-1), matching: matching,
            matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward
        )
        let later = gregorianCalendar.nextDate(
            after: start.addingTimeInterval(-1), matching: matching,
            matchingPolicy: .strict, repeatedTimePolicy: .last, direction: .forward
        )
        guard let earlier, matchesRequestedWallTime(earlier, date: localDate, time: localTime) else {
            throw LocaleFormattingFailureV1.nonexistentDSTTime
        }
        guard let later, matchesRequestedWallTime(later, date: localDate, time: localTime) else {
            throw LocaleFormattingFailureV1.nonexistentDSTTime
        }
        guard earlier != later else { return earlier }
        switch disambiguation {
        case .requireExplicit: throw LocaleFormattingFailureV1.ambiguousDSTTimeRequiresChoice
        case .earlier: return earlier
        case .later: return later
        }
    }

    func formatDecimal(_ value: Decimal) throws -> String {
        try formatStrict(value, formatter: decimalFormatter)
    }

    func parseDecimal(_ value: String) throws -> Decimal {
        try parseStrict(value, formatter: decimalFormatter)
    }

    func formatCurrency(_ value: LocaleCurrencyAmountV1) throws -> String {
        let formatter = currencyFormatter(currencyCode: value.currencyCode)
        return try formatStrict(value.amount, formatter: formatter)
    }

    func parseCurrency(_ value: String, currencyCode: String) throws -> LocaleCurrencyAmountV1 {
        let code = try LocaleCurrencyAmountV1(amount: 0, currencyCode: currencyCode).currencyCode
        return try LocaleCurrencyAmountV1(amount: parseStrict(value, formatter: currencyFormatter(currencyCode: code)), currencyCode: code)
    }

    func formatPercent(_ value: Decimal) throws -> String {
        try formatStrict(value, formatter: percentFormatter)
    }

    /// Returns the canonical fractional value (for example `0.125` for
    /// twelve-and-a-half percent), never the rendered percent text.
    func parsePercent(_ value: String) throws -> Decimal {
        try parseStrict(value, formatter: percentFormatter)
    }

    func formatLength(_ value: Decimal, canonicalUnit: LocaleLengthUnitV1) throws -> String {
        guard !value.isNaN else { throw LocaleFormattingFailureV1.invalidLocalizedInput }
        let displayUnit: LocaleLengthUnitV1 = profile.units == .metric ? .meters : .feet
        let displayValue = try convertedLength(value, from: canonicalUnit, to: displayUnit)
        let rendered = try renderLength(displayValue, unit: displayUnit)
        guard try parseLengthUnchecked(
            rendered, displayedUnit: displayUnit, canonicalUnit: canonicalUnit
        ) == value else {
            throw LocaleFormattingFailureV1.lossyLocalizedRoundTrip
        }
        return rendered
    }

    /// Both source and target units are required. This rejects an unrecognized
    /// localized label instead of guessing a unit from a region or language.
    func parseLength(
        _ value: String,
        displayedUnit: LocaleLengthUnitV1,
        canonicalUnit: LocaleLengthUnitV1
    ) throws -> LocaleLengthAmountV1 {
        let parsed = try parseLengthUnchecked(
            value, displayedUnit: displayedUnit, canonicalUnit: canonicalUnit
        )
        let displayValue = try convertedLength(parsed, from: canonicalUnit, to: displayedUnit)
        guard try renderLength(displayValue, unit: displayedUnit) == value else {
            throw LocaleFormattingFailureV1.lossyLocalizedRoundTrip
        }
        return try LocaleLengthAmountV1(value: parsed, canonicalUnit: canonicalUnit)
    }

    func weekRules() -> LocaleWeekRulesV1 {
        let calendar = presentationCalendar
        return LocaleWeekRulesV1(
            firstWeekday: calendar.firstWeekday,
            minimumDaysInFirstWeek: calendar.minimumDaysInFirstWeek
        )
    }

    /// Paper is an explicit report-layout choice and is never inferred from a
    /// language, postal address, storefront, or project jurisdiction.
    func paperLayout(_ requested: LocalePaperSizeV1) -> LocalePaperLayoutV1 {
        switch requested {
        case .usLetter: return LocalePaperLayoutV1(paperSize: .usLetter, widthPoints: 612, heightPoints: 792)
        case .a4: return LocalePaperLayoutV1(paperSize: .a4, widthPoints: 595.28, heightPoints: 841.89)
        }
    }

    /// Freeform address lines are opaque authored text. This validates only
    /// presentation safety and does not infer a country or restructure fields.
    func preservedAddressLines(_ lines: [String]) throws -> [String] {
        guard !lines.isEmpty, lines.allSatisfy({ !$0.isEmpty && !$0.contains("\u{0000}") }) else {
            throw LocaleFormattingFailureV1.invalidAddressPresentation
        }
        return lines
    }

    /// Foundation has no public, locale-complete telephone formatter. Keep the
    /// supplied value intact so extensions, international prefixes, and source
    /// formatting are never discarded or silently normalized.
    func preservedPhone(_ value: String) throws -> String {
        guard !value.isEmpty, !value.contains("\u{0000}") else {
            throw LocaleFormattingFailureV1.invalidPhonePresentation
        }
        return value
    }

    /// DatePicker supplies an instant in its environment's time zone. Extract
    /// the Gregorian day there before encoding the canonical storage string.
    static func canonicalGregorianDate(containing instant: Date, timeZone: TimeZone) throws -> LocaleGregorianDateV1 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            throw LocaleFormattingFailureV1.invalidGregorianDate
        }
        return try LocaleGregorianDateV1(year: year, month: month, day: day)
    }

    static func decodeCanonicalGregorianDate(_ value: String) throws -> LocaleGregorianDateV1 {
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else {
            throw LocaleFormattingFailureV1.invalidGregorianDate
        }
        let result = try LocaleGregorianDateV1(year: year, month: month, day: day)
        guard result.canonicalString == value else { throw LocaleFormattingFailureV1.invalidGregorianDate }
        return result
    }

    /// Frozen civil values are not instants in the current time zone.
    static func displayCanonicalLocalDate(_ value: String, locale: Locale) throws -> String {
        let day = try decodeCanonicalGregorianDate(value)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let anchor = calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day, hour: 12
        )) else { throw LocaleFormattingFailureV1.invalidGregorianDate }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = locale.calendar
        formatter.timeZone = .gmt
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: anchor)
    }

    static func displayCanonicalLocalTime(_ value: String, locale: Locale) throws -> String {
        let wall = try LocaleWallTimeV1(canonicalString: value)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let anchor = calendar.date(from: DateComponents(
            year: 2000, month: 1, day: 1, hour: wall.hour, minute: wall.minute, second: wall.second
        )) else { throw LocaleFormattingFailureV1.invalidWallTime }
        return wallTimeFormatter(locale: locale).string(from: anchor)
    }

    private static func wallTimeFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = locale.calendar
        formatter.timeZone = .gmt
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        formatter.isLenient = false
        return formatter
    }

    private var locale: Locale {
        Locale(identifier: profile.localeIdentifier + "@numbers=" + profile.numberingSystem.rawValue)
    }

    private var timeZone: TimeZone { resolvedTimeZone }

    private var presentationCalendar: Calendar {
        var calendar = Calendar(identifier: profile.calendar.foundationIdentifier)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .gmt
        return calendar
    }

    private var decimalFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 38
        return formatter
    }

    private var percentFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.generatesDecimalNumbers = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 38
        return formatter
    }

    private func currencyFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.generatesDecimalNumbers = true
        // Retain Foundation's currency-specific minimum (USD two, JPY zero).
        // Additional authored precision remains visible; this layer does not
        // quantize stored amounts or impose payment-settlement rules.
        formatter.maximumFractionDigits = 38
        return formatter
    }

    private func dateFormatter(dateStyle: DateStyleV1, timeStyle: TimeStyleV1?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = presentationCalendar
        formatter.timeZone = timeZone
        formatter.isLenient = false
        formatter.dateStyle = foundationDateStyle(dateStyle)
        formatter.timeStyle = timeStyle.map(foundationTimeStyle) ?? .none
        return formatter
    }

    /// A civil Gregorian date is rendered in a fixed zone so skipped civil
    /// days (for example a historical zone-date skip) cannot shift it.
    private func civilDateFormatter(style: DateStyleV1) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = presentationCalendar
        formatter.timeZone = .gmt
        formatter.isLenient = false
        formatter.dateStyle = foundationDateStyle(style)
        formatter.timeStyle = .none
        return formatter
    }

    private func parseStrict(_ value: String, formatter: NumberFormatter) throws -> Decimal {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let number = formatter.number(from: value) else {
            throw LocaleFormattingFailureV1.invalidLocalizedInput
        }
        let decimal = number.decimalValue
        guard !decimal.isNaN,
              formatter.string(from: NSDecimalNumber(decimal: decimal)) == value else {
            throw LocaleFormattingFailureV1.lossyLocalizedRoundTrip
        }
        return decimal
    }

    private func formatStrict(_ value: Decimal, formatter: NumberFormatter) throws -> String {
        guard !value.isNaN,
              let rendered = formatter.string(from: NSDecimalNumber(decimal: value)),
              try parseStrict(rendered, formatter: formatter) == value else {
            throw LocaleFormattingFailureV1.lossyLocalizedRoundTrip
        }
        return rendered
    }

    private func renderLength(_ value: Decimal, unit: LocaleLengthUnitV1) throws -> String {
        let number = try formatDecimal(value)
        let label = localizedLengthLabel(unit)
        guard !label.isEmpty else { throw LocaleFormattingFailureV1.invalidLocalizedInput }
        return number + " " + label
    }

    private func parseLengthUnchecked(
        _ value: String,
        displayedUnit: LocaleLengthUnitV1,
        canonicalUnit: LocaleLengthUnitV1
    ) throws -> Decimal {
        let label = localizedLengthLabel(displayedUnit)
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty,
              value.hasSuffix(label) else {
            throw LocaleFormattingFailureV1.invalidLocalizedInput
        }
        let numberPart = String(value.dropLast(label.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numberPart.isEmpty else { throw LocaleFormattingFailureV1.invalidLocalizedInput }
        return try convertedLength(
            try parseDecimal(numberPart), from: displayedUnit, to: canonicalUnit
        )
    }

    private func localizedLengthLabel(_ unit: LocaleLengthUnitV1) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        return formatter.string(from: foundationUnit(unit))
    }

    private func convertedLength(
        _ value: Decimal,
        from source: LocaleLengthUnitV1,
        to target: LocaleLengthUnitV1
    ) throws -> Decimal {
        guard !value.isNaN else { throw LocaleFormattingFailureV1.invalidLocalizedInput }
        guard source != target else { return value }
        let result = try convertedLengthExactly(value, from: source, to: target)
        guard !result.isNaN,
              try convertedLengthExactly(result, from: target, to: source) == value else {
            throw LocaleFormattingFailureV1.lossyLocalizedRoundTrip
        }
        return result
    }

    private func convertedLengthExactly(
        _ value: Decimal,
        from source: LocaleLengthUnitV1,
        to target: LocaleLengthUnitV1
    ) throws -> Decimal {
        var feetToMeters = Decimal(3048) / Decimal(10_000)
        var operand = value
        var result = Decimal()
        let status: NSDecimalNumber.CalculationError
        switch (source, target) {
        case (.feet, .meters):
            status = NSDecimalMultiply(&result, &operand, &feetToMeters, .plain)
        case (.meters, .feet):
            status = NSDecimalDivide(&result, &operand, &feetToMeters, .plain)
        case (.meters, .meters), (.feet, .feet): return value
        }
        guard status == .noError else {
            throw LocaleFormattingFailureV1.lossyLocalizedRoundTrip
        }
        return result
    }

    private func gregorianDisplayAnchor(_ value: LocaleGregorianDateV1) -> Date? {
        utcGregorianCalendar.date(from: DateComponents(
            timeZone: .gmt, year: value.year, month: value.month, day: value.day, hour: 12
        ))
    }

    private func foundationUnit(_ unit: LocaleLengthUnitV1) -> UnitLength {
        switch unit { case .meters: return .meters; case .feet: return .feet }
    }

    private func foundationDateStyle(_ value: DateStyleV1) -> DateFormatter.Style {
        switch value { case .short: return .short; case .medium: return .medium; case .long: return .long }
    }

    private func foundationTimeStyle(_ value: TimeStyleV1) -> DateFormatter.Style {
        switch value { case .short: return .short; case .medium: return .medium }
    }

    private func isASCIIOnlyNumericDate(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || $0 == "/" || $0 == "-" || $0 == "."
        }
    }

    private func required(_ value: Int?) throws -> Int {
        guard let value else { throw LocaleFormattingFailureV1.invalidGregorianDate }
        return value
    }

    private func matchesRequestedWallTime(
        _ instant: Date,
        date: LocaleGregorianDateV1,
        time: LocaleWallTimeV1
    ) -> Bool {
        let actual = gregorianCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: instant
        )
        return actual.year == date.year && actual.month == date.month && actual.day == date.day
            && actual.hour == time.hour && actual.minute == time.minute && actual.second == time.second
    }
}

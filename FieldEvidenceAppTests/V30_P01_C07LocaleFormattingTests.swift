import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P01C07LocaleFormattingTests: XCTestCase {
    func testCanonicalDateGrammarAndLeapDay() throws {
        let date = try LocaleFormattingServiceV1.decodeCanonicalGregorianDate("2024-02-29")
        XCTAssertEqual(date.canonicalString, "2024-02-29")
        for input in try strings("invalidCanonicalDates") {
            XCTAssertThrowsError(try LocaleFormattingServiceV1.decodeCanonicalGregorianDate(input), input)
        }
        XCTAssertThrowsError(try LocaleGregorianDateV1(year: 10000, month: 1, day: 1))
        XCTAssertThrowsError(try JSONDecoder().decode(
            LocaleGregorianDateV1.self, from: Data(#"{"year":2025,"month":2,"day":29}"#.utf8)
        ))
        XCTAssertThrowsError(try JSONDecoder().decode(
            LocaleWallTimeV1.self, from: Data(#"{"hour":25,"minute":0,"second":0}"#.utf8)
        ))
    }

    func testDatePickerBoundaryUsesItsTimeZoneAndGregorianStorage() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-01-01T01:00:00Z"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(try LocaleFormattingServiceV1.canonicalGregorianDate(
            containing: instant, timeZone: losAngeles).canonicalString, "2023-12-31")
        XCTAssertEqual(try LocaleFormattingServiceV1.canonicalGregorianDate(
            containing: instant, timeZone: .gmt).canonicalString, "2024-01-01")
    }

    func testSixLocalesRoundTripWithoutChangingCanonicalValues() throws {
        let day = try LocaleGregorianDateV1(year: 2024, month: 2, day: 29)
        let decimal = try XCTUnwrap(Decimal(string: "1234.125", locale: Locale(identifier: "en_US_POSIX")))
        let money = try LocaleCurrencyAmountV1(amount: decimal, currencyCode: "USD")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(day)
        for identifier in try strings("locales") {
            let service = try formatter(identifier)
            XCTAssertEqual(try service.parseDisplayedGregorianDate(service.displayGregorianDate(day)), day, identifier)
            XCTAssertEqual(try service.parseDecimal(service.formatDecimal(decimal)), decimal, identifier)
            XCTAssertEqual(try service.parseCurrency(service.formatCurrency(money), currencyCode: "USD"), money, identifier)
            XCTAssertEqual(try service.parsePercent(service.formatPercent(Decimal(string: "0.125")!)),
                           Decimal(string: "0.125")!, identifier)
            XCTAssertEqual(try encoder.encode(day), before)
        }
    }

    func testAmbiguousAndPartiallyConsumedInputIsRejected() throws {
        let service = try formatter("en-US")
        for value in try strings("ambiguousDates") {
            XCTAssertThrowsError(try service.parseDisplayedGregorianDate(value), value)
        }
        for value in try strings("invalidNumbers") {
            XCTAssertThrowsError(try service.parseDecimal(value), value)
        }
        XCTAssertThrowsError(try service.parseCurrency("$12 trailing", currencyCode: "USD"))
        XCTAssertThrowsError(try service.parsePercent("12% trailing"))
        XCTAssertThrowsError(try LocaleCurrencyAmountV1(amount: 1, currencyCode: "ZZZ"))
        XCTAssertEqual(try service.formatCurrency(LocaleCurrencyAmountV1(amount: 1, currencyCode: "USD")), "$1.00")
        XCTAssertEqual(try service.parseCurrency("$1.00", currencyCode: "USD").amount, 1)
    }

    func testDSTGapNeverMovesWorkToAnotherDayAndFoldRequiresChoice() throws {
        let service = try formatter("en-US", zone: "America/New_York")
        let gap = try LocaleGregorianDateV1(year: 2024, month: 3, day: 10)
        let wall = try LocaleWallTimeV1(hour: 2, minute: 30)
        XCTAssertThrowsError(try service.resolveInstant(localDate: gap, localTime: wall)) {
            XCTAssertEqual($0 as? LocaleFormattingFailureV1, .nonexistentDSTTime)
        }
        let fold = try LocaleGregorianDateV1(year: 2024, month: 11, day: 3)
        let repeated = try LocaleWallTimeV1(hour: 1, minute: 30)
        XCTAssertThrowsError(try service.resolveInstant(localDate: fold, localTime: repeated)) {
            XCTAssertEqual($0 as? LocaleFormattingFailureV1, .ambiguousDSTTimeRequiresChoice)
        }
        let earlier = try service.resolveInstant(localDate: fold, localTime: repeated, disambiguation: .earlier)
        let later = try service.resolveInstant(localDate: fold, localTime: repeated, disambiguation: .later)
        XCTAssertEqual(later.timeIntervalSince(earlier), 3600)
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(iso.string(from: earlier), "2024-11-03T05:30:00Z")
        XCTAssertEqual(iso.string(from: later), "2024-11-03T06:30:00Z")
    }

    func testWallClockRoundTripsAndDoesNotGuessAMPMOrADate() throws {
        let wall = try LocaleWallTimeV1(canonicalString: "15:02:03")
        XCTAssertEqual(wall.canonicalString, "15:02:03")
        for identifier in try strings("locales") {
            let service = try formatter(identifier)
            XCTAssertEqual(try service.parseDisplayedWallTime(service.displayWallTime(wall)), wall, identifier)
        }
        let us = try formatter("en-US")
        let gb = try formatter("en-GB")
        XCTAssertNotEqual(try us.displayWallTime(wall), try gb.displayWallTime(wall))
        XCTAssertThrowsError(try us.parseDisplayedWallTime("3:02:03"))
        XCTAssertThrowsError(try gb.parseDisplayedWallTime("15:02:03 trailing"))
        for invalid in ["24:00:00", "15:60:00", "15:02", "1:02:03", "١٥:٠٢:٠٣"] {
            XCTAssertThrowsError(try LocaleWallTimeV1(canonicalString: invalid), invalid)
        }
        let skipped = try formatter("en-US", zone: "Pacific/Apia")
        XCTAssertThrowsError(try skipped.resolveInstant(
            localDate: LocaleGregorianDateV1(year: 2011, month: 12, day: 30), localTime: wall
        )) {
            XCTAssertEqual($0 as? LocaleFormattingFailureV1, .nonexistentDSTTime)
        }
    }

    func testCivilDaySurvivesSkippedTimeZoneDayAndNonGregorianPresentation() throws {
        let day = try LocaleGregorianDateV1(year: 2011, month: 12, day: 30)
        let apia = try formatter("en-US", zone: "Pacific/Apia")
        XCTAssertEqual(try apia.parseDisplayedGregorianDate(apia.displayGregorianDate(day)), day)
        for calendar in [GlobalizationCalendarV1.buddhist, .japanese] {
            let service = try formatter("en-US", calendar: calendar)
            XCTAssertEqual(try service.parseDisplayedGregorianDate(service.displayGregorianDate(day)), day)
        }
        let instant = Date(timeIntervalSince1970: 0)
        XCTAssertNotEqual(try formatter("en-US", zone: "America/New_York").displayInstant(instant),
                          try formatter("en-US", zone: "Asia/Tokyo").displayInstant(instant))
        XCTAssertEqual(instant.timeIntervalSince1970, 0)
    }

    func testUnitsWeekPaperAndAuthoredContactData() throws {
        let metric = try formatter("en-US", units: .metric)
        let customary = try formatter("en-US", units: .usCustomary)
        XCTAssertNotEqual(try metric.formatLength(1, canonicalUnit: .feet),
                          try customary.formatLength(1, canonicalUnit: .feet))
        XCTAssertEqual(metric.weekRules().firstWeekday, 1)
        XCTAssertEqual(try formatter("en-GB").weekRules().firstWeekday, 2)
        XCTAssertEqual(try formatter("en-GB").weekRules().minimumDaysInFirstWeek, 4)
        XCTAssertEqual(metric.paperLayout(.usLetter).widthPoints, 612)
        XCTAssertEqual(metric.paperLayout(.a4).widthPoints, 595.28, accuracy: 0.001)
        let address = try strings("authoredAddress")
        let phone = try XCTUnwrap(try fixture()["authoredPhone"] as? String)
        XCTAssertEqual(try metric.preservedAddressLines(address), address)
        XCTAssertEqual(try metric.preservedPhone(phone), phone)
    }

    func testExistingCatalogFormattingUsesChosenLocaleIndependentlyOfEnglishCatalog() {
        let locale = Locale(identifier: "de_DE")
        let number = NumberFormatter()
        number.locale = locale
        number.numberStyle = .decimal
        XCTAssertEqual(BundledLocalizationCatalogV1.formattedInteger(1234, regionSource: locale),
                       number.string(from: 1234))
        let date = DateFormatter()
        date.locale = locale
        date.calendar = locale.calendar
        date.timeZone = .gmt
        date.dateStyle = .medium
        date.timeStyle = .short
        let instant = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(BundledLocalizationCatalogV1.formattedDate(
            instant, timeZone: .gmt, regionSource: locale), date.string(from: instant))
    }

    func testNumberingSystemIsIndependentAndCanonicalGrammarStaysASCII() throws {
        let arabic = try LocaleFormattingServiceV1(profile: FormattingLocaleProfileV1(
            localeIdentifier: "ar-EG", ianaTimeZoneIdentifier: "Africa/Cairo",
            calendar: .gregorian, numberingSystem: .arabicIndic, units: .metric
        ))
        let latin = try LocaleFormattingServiceV1(profile: FormattingLocaleProfileV1(
            localeIdentifier: "ar-EG", ianaTimeZoneIdentifier: "Africa/Cairo",
            calendar: .gregorian, numberingSystem: .latin, units: .metric
        ))
        let value = try XCTUnwrap(Decimal(string: "1234.5"))
        XCTAssertNotEqual(try arabic.formatDecimal(value), try latin.formatDecimal(value))
        XCTAssertEqual(try arabic.parseDecimal(arabic.formatDecimal(value)), value)
        XCTAssertEqual(try LocaleGregorianDateV1(year: 2024, month: 2, day: 29).canonicalString, "2024-02-29")
        XCTAssertThrowsError(try LocaleFormattingServiceV1.decodeCanonicalGregorianDate("٢٠٢٤-٠٢-٢٩"))
    }

    func testLengthGrammarRequiresExplicitUnitsAndPreservesCanonicalQuantity() throws {
        let service = try formatter("en-US", units: .metric)
        let display = try service.formatLength(1, canonicalUnit: .feet)
        let parsed = try service.parseLength(display, displayedUnit: .meters, canonicalUnit: .feet)
        XCTAssertEqual(parsed.value, 1)
        XCTAssertEqual(parsed.canonicalUnit, .feet)
        XCTAssertThrowsError(try service.parseLength(display, displayedUnit: .feet, canonicalUnit: .feet))
        XCTAssertThrowsError(try service.parseLength("1", displayedUnit: .meters, canonicalUnit: .feet))
        XCTAssertThrowsError(try service.parseLength(display + " trailing", displayedUnit: .meters, canonicalUnit: .feet))
        XCTAssertThrowsError(try service.formatLength(.nan, canonicalUnit: .meters))
        let customary = try formatter("en-US", units: .usCustomary)
        XCTAssertThrowsError(try customary.formatLength(1, canonicalUnit: .meters))
    }

    func testSignedZeroCurrencyAndLocaleSeparators() throws {
        let us = try formatter("en-US")
        let german = try formatter("de-DE")
        XCTAssertEqual(try us.parseDecimal("1,234.5"), Decimal(string: "1234.5"))
        XCTAssertEqual(try german.parseDecimal("1.234,5"), Decimal(string: "1234.5"))
        XCTAssertThrowsError(try german.parseDecimal("1,234.5"))
        for amount in [Decimal(-12), 0, 12] {
            for currency in ["USD", "JPY", "EUR"] {
                let money = try LocaleCurrencyAmountV1(amount: amount, currencyCode: currency)
                XCTAssertEqual(try german.parseCurrency(german.formatCurrency(money), currencyCode: currency), money)
            }
        }
    }

    func testHighPrecisionEitherRoundTripsExactlyOrFailsExplicitly() throws {
        let service = try formatter("en-US")
        let source = try XCTUnwrap(Decimal(string: "12345678901234567890.123456789012345678",
                                           locale: Locale(identifier: "en_US_POSIX")))
        do {
            let display = try service.formatDecimal(source)
            XCTAssertEqual(try service.parseDecimal(display), source)
        } catch {
            XCTAssertEqual(error as? LocaleFormattingFailureV1, .lossyLocalizedRoundTrip)
        }
        XCTAssertThrowsError(try service.formatDecimal(.nan))
        XCTAssertThrowsError(try service.formatPercent(.nan))
        XCTAssertThrowsError(try LocaleCurrencyAmountV1(amount: .nan, currencyCode: "USD"))
    }

    func testDecodedProfileCannotSilentlyFallBackToGMT() throws {
        let original = try FormattingLocaleProfileV1(
            localeIdentifier: "en-US", ianaTimeZoneIdentifier: "America/New_York",
            calendar: .gregorian, numberingSystem: .latin, units: .metric
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)) as? [String: Any])
        object["ianaTimeZoneIdentifier"] = "Invalid/Zone"
        let decoded = try JSONDecoder().decode(
            FormattingLocaleProfileV1.self, from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertThrowsError(try LocaleFormattingServiceV1(profile: decoded)) {
            XCTAssertEqual($0 as? GlobalizationAxisFailureV1, .invalidTimeZone)
        }
    }

    private func formatter(
        _ locale: String, zone: String = "America/New_York",
        calendar: GlobalizationCalendarV1 = .gregorian,
        units: GlobalizationUnitsV1 = .metric
    ) throws -> LocaleFormattingServiceV1 {
        try LocaleFormattingServiceV1(profile: FormattingLocaleProfileV1(
            localeIdentifier: locale, ianaTimeZoneIdentifier: zone,
            calendar: calendar, numberingSystem: .latin, units: units
        ))
    }

    private func strings(_ key: String) throws -> [String] {
        try XCTUnwrap(try fixture()[key] as? [String])
    }

    private func fixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/LocaleFormatting/formatting-grammar-cases-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}

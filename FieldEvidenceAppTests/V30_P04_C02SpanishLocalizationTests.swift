import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Locale-exclusive draft resources. Native execution and professional review
/// remain separate gates; loading these files does not activate a shipping locale.
final class V30_P04_C02SpanishLocalizationTests: XCTestCase {
    func testAllSpanishLanesPreserveEnglishKeysAndTypedResourceStructure() throws {
        let fixture = try load("FieldEvidenceAppTests/Fixtures/V30/Locales/es.json")
        let expected = try XCTUnwrap(fixture["laneCounts"] as? [String: Int])
        let source = try load("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let english = try XCTUnwrap(source["strings"] as? [String: [String: Any]])
        var allKeys = Set<String>()
        for lane in ["app", "report", "accessibility"] {
            let catalog = try load("FieldEvidenceApp/Resources/Globalization/es.\(lane).json")
            XCTAssertEqual(catalog["locale"] as? String, "es")
            XCTAssertEqual(catalog["status"] as? String, "DRAFT_NONSHIPPING")
            XCTAssertEqual(catalog["machineAssisted"] as? Bool, true)
            let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
            XCTAssertEqual(strings.count, expected[lane])
            for (key, entry) in strings {
                XCTAssertTrue(allKeys.insert(key).inserted, "Duplicate lane key: \(key)")
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]])
                XCTAssertEqual(Set(localizations.keys), Set(["en", "es"]))
                let en = try XCTUnwrap(localizations["en"])
                let es = try XCTUnwrap(localizations["es"])
                try assertParallel(en, es, key)
                if let baseline = english[key]?["localizations"] as? [String: Any],
                   let baselineEnglish = baseline["en"] as? [String: Any] {
                    XCTAssertTrue(NSDictionary(dictionary: en).isEqual(to: baselineEnglish), key)
                }
            }
        }
        XCTAssertEqual(allKeys.count, fixture["sourceCount"] as? Int)
        XCTAssertTrue(Set(english.keys).isSubset(of: allKeys))
    }

    func testSpanishRegionalPreferencesResolveToTheSameBaseResource() throws {
        for profile in ["es-US", "es-MX", "es-419"] {
            let resolution = SystemLanguageResolverV1().resolve(
                preferredLanguageIdentifiers: [profile], declaredLocalizationIdentifiers: ["en", "es"])
            XCTAssertEqual(resolution.effectiveLanguage.rawValue, "es")
            XCTAssertEqual(resolution.resourceIdentifier, "es")
            XCTAssertEqual(resolution.provenance, .baseLanguageResource)
            let fallback = SystemLanguageResolverV1().resolve(
                preferredLanguageIdentifiers: [profile], declaredLocalizationIdentifiers: ["en"])
            XCTAssertEqual(fallback.effectiveLanguage, .english)
            XCTAssertEqual(fallback.provenance, .englishFallback)
        }
    }

    func testSpanishProfilesRoundTripFormattingWithoutChangingCanonicalValues() throws {
        let canonicalDate = try LocaleGregorianDateV1(year: 2026, month: 9, day: 22)
        let time = try LocaleWallTimeV1(hour: 14, minute: 5, second: 9)
        let amount = try XCTUnwrap(Decimal(string: "12345.625", locale: Locale(identifier: "en_US_POSIX")))
        for profile in ["es-US", "es-MX", "es-419"] {
            let formatting = try FormattingLocaleProfileV1(localeIdentifier: profile,
                ianaTimeZoneIdentifier: "America/New_York", calendar: .gregorian,
                numberingSystem: .latin, units: .usCustomary)
            let service = try LocaleFormattingServiceV1(profile: formatting)
            XCTAssertEqual(try service.parseDecimal(service.formatDecimal(amount)), amount)
            XCTAssertEqual(try service.parseDisplayedWallTime(service.displayWallTime(time)), time)
            XCTAssertFalse(service.displayGregorianDate(canonicalDate).isEmpty)
            XCTAssertEqual(canonicalDate.canonicalString, "2026-09-22")
            XCTAssertEqual(try service.preservedPhone("+1 212 555 0100"), "+1 212 555 0100")
            let address = ["123 Example St", "Synthetic City, NY 10001"]
            XCTAssertEqual(try service.preservedAddressLines(address), address)
        }
    }

    @MainActor
    func testSpanishCriticalCopyKeepsConfirmationTokenAndPermissionPurpose() throws {
        let strings = try catalogStrings("accessibility")
        let erase = try direct(strings, "v30.critical.erase-confirmation")
        XCTAssertEqual(String(format: erase, locale: Locale(identifier: "es-US"), EraseAllService.requiredConfirmation),
                       "Escriba ERASE para confirmar.")
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"] {
            let value = try direct(strings, key)
            XCTAssertFalse(value.isEmpty)
            XCTAssertTrue(value.contains("iPhone"))
        }
        let denied = try direct(strings, "v30.critical.failure.permission-denied")
        XCTAssertTrue(denied.contains("denegó"))
        XCTAssertTrue(denied.contains("alternativa"))
        XCTAssertFalse(LocalizedSyncStatePresentationV1.remoteSyncUnavailable.permitsSuccessAnnouncement)
    }

    func testSpanishReviewBundleKeepsDraftAndStorefrontBoundaries() throws {
        let bundle = try load("docs/design/v30/locales/es/V30P04C02ReviewPacketV1.json")
        XCTAssertEqual(bundle["status"] as? String, "DRAFT_NONSHIPPING")
        XCTAssertEqual(bundle["linguisticAcceptance"] as? Bool, false)
        let packet = try XCTUnwrap(bundle["reviewPacket"] as? [String: Any])
        XCTAssertEqual(packet["status"] as? String, "DRAFT_NONSHIPPING")
        XCTAssertEqual(packet["machineAssisted"] as? Bool, true)
        XCTAssertTrue(packet["candidateTuple"] is NSNull)
        XCTAssertTrue(packet["receipt"] is NSNull)
        let metadata = try XCTUnwrap(bundle["metadataDraft"] as? [String: Any])
        XCTAssertEqual(metadata["appStoreLanguage"] as? String, "Spanish (Mexico)")
        XCTAssertEqual(metadata["storefront"] as? String, "US")
        XCTAssertEqual(metadata["publicationAuthorized"] as? Bool, false)
    }

    private func assertParallel(_ english: [String: Any], _ spanish: [String: Any], _ key: String) throws {
        XCTAssertEqual(Set(english.keys), Set(spanish.keys), key)
        for (field, value) in english {
            if field == "stringUnit" {
                let en = try XCTUnwrap(value as? [String: String])
                let es = try XCTUnwrap(spanish[field] as? [String: String])
                let source = try XCTUnwrap(en["value"])
                let target = try XCTUnwrap(es["value"])
                XCTAssertEqual(es["state"], "needs_review", key)
                XCTAssertFalse(target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
                XCTAssertFalse(target.contains("\u{FFFD}"), key)
                XCTAssertEqual(try tokens(source), try tokens(target), key)
            } else if let en = value as? [String: Any] {
                let spanishChild = try XCTUnwrap(spanish[field] as? [String: Any])
                try assertParallel(en, spanishChild, key + "." + field)
            } else {
                XCTAssertTrue((value as? NSObject)?.isEqual(spanish[field]) == true, key + "." + field)
            }
        }
    }

    private func tokens(_ value: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(?:@|lld|llu|ld|lu|d|u|f)|%#@[A-Za-z_][A-Za-z0-9_]*@|%arg|%%"#)
        let text = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range) }.sorted()
    }

    private func catalogStrings(_ lane: String) throws -> [String: [String: Any]] {
        try XCTUnwrap(load("FieldEvidenceApp/Resources/Globalization/es.\(lane).json")["strings"] as? [String: [String: Any]])
    }

    private func direct(_ strings: [String: [String: Any]], _ key: String) throws -> String {
        let localizations = try XCTUnwrap(strings[key]?["localizations"] as? [String: [String: Any]])
        let unit = try XCTUnwrap(localizations["es"]?["stringUnit"] as? [String: String])
        return try XCTUnwrap(unit["value"])
    }

    private func load(_ relative: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(relative))) as? [String: Any])
    }
}

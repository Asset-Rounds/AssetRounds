import Foundation

/// Fail-closed validation for the presentation facts introduced by V30. These
/// facts describe how values are shown; they are never workspace truth.
enum GlobalizationAxisFailureV1: Error, Equatable, Sendable {
    case invalidAppLanguageTag
    case invalidFormattingLocale
    case invalidTimeZone
    case invalidCalendar
    case invalidNumberingSystem
    case invalidUnits
    case invalidAuthoredContentLanguage
    case invalidReportLanguageSelection
    case invalidStorefrontCountry
    case invalidProjectJurisdiction
    case canonicalIdentityContamination
}

struct AppLanguageTagV1: Codable, Equatable, Hashable, Sendable {
    static let supportedRawValues: Set<String> = ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]
    static let english = try! AppLanguageTagV1("en")

    let rawValue: String

    init(_ rawValue: String) throws {
        guard Self.supportedRawValues.contains(rawValue) else {
            throw GlobalizationAxisFailureV1.invalidAppLanguageTag
        }
        self.rawValue = rawValue
    }

    static func isWellFormedBCP47(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64, !value.contains("_"),
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        let components = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let language = components.first,
              (2...3).contains(language.count), language.allSatisfy({ $0.isASCII && $0.isLowercase }) else {
            return false
        }
        var sawScript = false
        var sawRegion = false
        for component in components.dropFirst() {
            guard !component.isEmpty else { return false }
            if component.count == 4, component.first?.isUppercase == true,
               component.dropFirst().allSatisfy({ $0.isASCII && $0.isLowercase }), !sawScript {
                sawScript = true
            } else if ((component.count == 2 && component.allSatisfy({ $0.isASCII && $0.isUppercase }))
                        || (component.count == 3 && component.allSatisfy({ $0.isASCII && $0.isNumber }))) && !sawRegion {
                sawRegion = true
            } else {
                return false
            }
        }
        return true
    }
}

enum GlobalizationCalendarV1: String, Codable, CaseIterable, Sendable {
    case gregorian = "GREGORIAN"
    case buddhist = "BUDDHIST"
    case japanese = "JAPANESE"

    var foundationIdentifier: Calendar.Identifier {
        switch self {
        case .gregorian: return .gregorian
        case .buddhist: return .buddhist
        case .japanese: return .japanese
        }
    }
}

enum GlobalizationNumberingSystemV1: String, Codable, CaseIterable, Sendable {
    case latin = "latn"
    case arabicIndic = "arab"
    case hanDecimal = "hanidec"
}

enum GlobalizationUnitsV1: String, Codable, CaseIterable, Sendable {
    case usCustomary = "US_CUSTOMARY"
    case metric = "METRIC"
}

struct FormattingLocaleProfileV1: Codable, Equatable, Sendable {
    let localeIdentifier: String
    let ianaTimeZoneIdentifier: String
    let calendar: GlobalizationCalendarV1
    let numberingSystem: GlobalizationNumberingSystemV1
    let units: GlobalizationUnitsV1

    init(
        localeIdentifier: String,
        ianaTimeZoneIdentifier: String,
        calendar: GlobalizationCalendarV1,
        numberingSystem: GlobalizationNumberingSystemV1,
        units: GlobalizationUnitsV1
    ) throws {
        guard AppLanguageTagV1.isWellFormedBCP47(localeIdentifier) else {
            throw GlobalizationAxisFailureV1.invalidFormattingLocale
        }
        guard TimeZone.knownTimeZoneIdentifiers.contains(ianaTimeZoneIdentifier) else {
            throw GlobalizationAxisFailureV1.invalidTimeZone
        }
        self.localeIdentifier = localeIdentifier
        self.ianaTimeZoneIdentifier = ianaTimeZoneIdentifier
        self.calendar = calendar
        self.numberingSystem = numberingSystem
        self.units = units
    }
}

enum AuthoredContentLanguageV1: Codable, Equatable, Sendable {
    case known(String)
    case unknown

    static func declared(_ value: String) throws -> Self {
        guard AppLanguageTagV1.isWellFormedBCP47(value) else {
            throw GlobalizationAxisFailureV1.invalidAuthoredContentLanguage
        }
        return .known(value)
    }
}

enum ReportLanguageFallbackV1: String, Codable, CaseIterable, Sendable {
    case exact = "EXACT"
    case englishWithUserConfirmation = "ENGLISH_WITH_USER_CONFIRMATION"
}

struct ReportLanguageSelectionV1: Codable, Equatable, Sendable {
    let requestedLanguage: AppLanguageTagV1
    let effectiveLanguage: AppLanguageTagV1
    let fallback: ReportLanguageFallbackV1

    init(
        requestedLanguage: AppLanguageTagV1,
        effectiveLanguage: AppLanguageTagV1,
        fallback: ReportLanguageFallbackV1
    ) throws {
        switch fallback {
        case .exact:
            guard requestedLanguage == effectiveLanguage else {
                throw GlobalizationAxisFailureV1.invalidReportLanguageSelection
            }
        case .englishWithUserConfirmation:
            guard requestedLanguage != AppLanguageTagV1.english,
                  effectiveLanguage == AppLanguageTagV1.english else {
                throw GlobalizationAxisFailureV1.invalidReportLanguageSelection
            }
        }
        self.requestedLanguage = requestedLanguage
        self.effectiveLanguage = effectiveLanguage
        self.fallback = fallback
    }
}

enum StorefrontCountryV1: String, Codable, CaseIterable, Sendable {
    case unitedStates = "US"
}

struct ProjectJurisdictionV1: Codable, Equatable, Sendable {
    let countryCode: String
    let subdivisionCode: String?

    init(countryCode: String, subdivisionCode: String? = nil) throws {
        guard countryCode == StorefrontCountryV1.unitedStates.rawValue else {
            throw GlobalizationAxisFailureV1.invalidProjectJurisdiction
        }
        if let subdivisionCode {
            guard subdivisionCode.count == 2,
                  subdivisionCode.allSatisfy({ $0.isASCII && $0.isUppercase }) else {
                throw GlobalizationAxisFailureV1.invalidProjectJurisdiction
            }
        }
        self.countryCode = countryCode
        self.subdivisionCode = subdivisionCode
    }

    var stableIdentifier: String {
        subdivisionCode.map { "\(countryCode)-\($0)" } ?? countryCode
    }
}

/// The six axes are intentionally separate values. Formatting consists of the
/// locale, zone, calendar, numbering system, and units subaxes.
struct GlobalizationAxisSetV1: Codable, Equatable, Sendable {
    let appLanguage: AppLanguageTagV1
    let formatting: FormattingLocaleProfileV1
    let authoredContentLanguage: AuthoredContentLanguageV1
    let reportLanguage: ReportLanguageSelectionV1
    let storefrontCountry: StorefrontCountryV1
    let projectJurisdiction: ProjectJurisdictionV1

    init(
        appLanguage: AppLanguageTagV1,
        formatting: FormattingLocaleProfileV1,
        authoredContentLanguage: AuthoredContentLanguageV1,
        reportLanguage: ReportLanguageSelectionV1,
        storefrontCountry: StorefrontCountryV1,
        projectJurisdiction: ProjectJurisdictionV1
    ) {
        self.appLanguage = appLanguage
        self.formatting = formatting
        self.authoredContentLanguage = authoredContentLanguage
        self.reportLanguage = reportLanguage
        self.storefrontCountry = storefrontCountry
        self.projectJurisdiction = projectJurisdiction
    }
}

/// Presentation choices must never enter a canonical mutation, identity, or
/// backup payload. Later cards bind this assertion to their exact byte tests.
enum GlobalizationCanonicalIdentityBoundaryV1 {
    static let languageOrFormattingChangesCanonicalIdentity = false
    static let backupIncludesAxisPreferences = false
    static let rawEnumValuesLocalized = false

    static func validateNoCanonicalIdentityMutation(_ changedFields: [String]) throws {
        guard changedFields.isEmpty else {
            throw GlobalizationAxisFailureV1.canonicalIdentityContamination
        }
    }
}

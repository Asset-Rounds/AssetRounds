import Foundation

enum ReportLanguageControlFailureV1: Error, Equatable, Sendable {
    case englishConfirmationRequired
    case unavailableReportLanguage
}

/// Report resources are independent of app UI resources. The incumbent PDF
/// renderer has English chrome; declaring an app locale never enables a report.
enum ReportLanguageControlPolicyV1 {
    static let requestableLanguages = ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]
        .map { try! AppLanguageTagV1($0) }

    static func resolve(
        requested: AppLanguageTagV1,
        confirmsEnglishFallback: Bool = false
    ) throws -> ReportLanguageSelectionV1 {
        _ = try AppLanguageTagV1(requested.rawValue)
        if requested == .english {
            return try .init(requestedLanguage: requested, effectiveLanguage: .english, fallback: .exact)
        }
        guard confirmsEnglishFallback else {
            throw ReportLanguageControlFailureV1.englishConfirmationRequired
        }
        return try .init(
            requestedLanguage: requested, effectiveLanguage: .english,
            fallback: .englishWithUserConfirmation
        )
    }

    static func validateForCurrentRenderer(_ selection: ReportLanguageSelectionV1) throws {
        _ = try AppLanguageTagV1(selection.requestedLanguage.rawValue)
        _ = try AppLanguageTagV1(selection.effectiveLanguage.rawValue)
        _ = try ReportLanguageSelectionV1(
            requestedLanguage: selection.requestedLanguage,
            effectiveLanguage: selection.effectiveLanguage, fallback: selection.fallback
        )
        guard selection.effectiveLanguage == .english else {
            throw ReportLanguageControlFailureV1.unavailableReportLanguage
        }
    }
}

/// A transient, explicit request at the existing render/delivery boundary.
/// requestedFormatting records a preference, NOT evidence that a frozen PDF
/// was reformatted. No renderer, font, catalog, or linguistic acceptance is
/// implied. Historical loads have no request; report/snapshot bytes stay fixed.
struct ReportLanguageRenderRequestV1: Equatable, Sendable {
    let selection: ReportLanguageSelectionV1
    let requestedFormatting: FormattingLocaleProfileV1

    init(selection: ReportLanguageSelectionV1, requestedFormatting: FormattingLocaleProfileV1) throws {
        self.selection = selection
        self.requestedFormatting = requestedFormatting
        try validate()
    }

    func validate() throws {
        try ReportLanguageControlPolicyV1.validateForCurrentRenderer(selection)
        _ = try FormattingLocaleProfileV1(
            localeIdentifier: requestedFormatting.localeIdentifier,
            ianaTimeZoneIdentifier: requestedFormatting.ianaTimeZoneIdentifier,
            calendar: requestedFormatting.calendar,
            numberingSystem: requestedFormatting.numberingSystem,
            units: requestedFormatting.units
        )
    }
}

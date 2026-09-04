import Foundation

enum LanguageResolutionFallbackV1: String, Codable, CaseIterable, Sendable {
    case exactDeclaredLanguage = "EXACT_DECLARED_LANGUAGE"
    case baseDeclaredLanguage = "BASE_DECLARED_LANGUAGE"
    case englishNoSupportedMatch = "ENGLISH_NO_SUPPORTED_MATCH"
}

struct LanguageResolutionV1: Codable, Equatable, Sendable {
    let requestedLanguage: String
    let effectiveLanguage: AppLanguageTagV1
    let fallback: LanguageResolutionFallbackV1
}

struct GlobalizationAxisResolutionRequestV1: Sendable {
    let preferredAppLanguageTags: [String]
    let formatting: FormattingLocaleProfileV1
    let authoredContentLanguage: AuthoredContentLanguageV1
    let reportLanguage: ReportLanguageSelectionV1?
    let storefrontCountry: StorefrontCountryV1
    let projectJurisdiction: ProjectJurisdictionV1

    init(
        preferredAppLanguageTags: [String],
        formatting: FormattingLocaleProfileV1,
        authoredContentLanguage: AuthoredContentLanguageV1,
        reportLanguage: ReportLanguageSelectionV1? = nil,
        storefrontCountry: StorefrontCountryV1 = .unitedStates,
        projectJurisdiction: ProjectJurisdictionV1
    ) throws {
        guard !preferredAppLanguageTags.isEmpty,
              preferredAppLanguageTags.allSatisfy(AppLanguageTagV1.isWellFormedBCP47) else {
            throw GlobalizationAxisFailureV1.invalidAppLanguageTag
        }
        self.preferredAppLanguageTags = preferredAppLanguageTags
        self.formatting = formatting
        self.authoredContentLanguage = authoredContentLanguage
        self.reportLanguage = reportLanguage
        self.storefrontCountry = storefrontCountry
        self.projectJurisdiction = projectJurisdiction
    }
}

struct GlobalizationAxisResolutionV1: Equatable, Sendable {
    let language: LanguageResolutionV1
    let axes: GlobalizationAxisSetV1
}

/// A pure resolver. It observes ordered system language tags and accepts the
/// other axes as explicit inputs; it never derives one axis from another.
enum GlobalizationAxisCoordinatorV1 {
    static func resolve(_ request: GlobalizationAxisResolutionRequestV1) throws -> GlobalizationAxisResolutionV1 {
        let language = try resolveLanguage(request.preferredAppLanguageTags)
        let report = try request.reportLanguage ?? ReportLanguageSelectionV1(
            requestedLanguage: language.effectiveLanguage,
            effectiveLanguage: language.effectiveLanguage,
            fallback: .exact
        )
        let axes = GlobalizationAxisSetV1(
            appLanguage: language.effectiveLanguage,
            formatting: request.formatting,
            authoredContentLanguage: request.authoredContentLanguage,
            reportLanguage: report,
            storefrontCountry: request.storefrontCountry,
            projectJurisdiction: request.projectJurisdiction
        )
        return GlobalizationAxisResolutionV1(language: language, axes: axes)
    }

    private static func resolveLanguage(_ preferred: [String]) throws -> LanguageResolutionV1 {
        for requested in preferred {
            guard AppLanguageTagV1.isWellFormedBCP47(requested) else {
                throw GlobalizationAxisFailureV1.invalidAppLanguageTag
            }
            if let exact = try? AppLanguageTagV1(requested) {
                return LanguageResolutionV1(
                    requestedLanguage: requested,
                    effectiveLanguage: exact,
                    fallback: .exactDeclaredLanguage
                )
            }
            if let base = AppLanguageTagV1.supportedRawValues
                .sorted(by: { $0.count > $1.count })
                .first(where: { requested.hasPrefix($0 + "-") }),
               let effective = try? AppLanguageTagV1(base) {
                return LanguageResolutionV1(
                    requestedLanguage: requested,
                    effectiveLanguage: effective,
                    fallback: .baseDeclaredLanguage
                )
            }
        }
        return LanguageResolutionV1(
            requestedLanguage: preferred[0],
            effectiveLanguage: .english,
            fallback: .englishNoSupportedMatch
        )
    }
}


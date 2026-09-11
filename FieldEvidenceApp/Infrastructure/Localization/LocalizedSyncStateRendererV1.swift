import Foundation

/// Bundle-only rendering; no reachability, network, notification scheduling,
/// language preference, canonical write, or authored-content substitution.
enum LocalizedSyncStateRendererV1 {
    static func text(
        _ presentation: LocalizedSyncStatePresentationV1,
        bundle: Bundle = .main, locale: Locale? = nil
    ) -> String {
        text(presentation.messageKey, bundle: bundle, locale: locale)
    }

    static func text(
        _ key: LocalizedSyncStateMessageKeyV1,
        bundle: Bundle = .main, locale: Locale? = nil
    ) -> String {
        let languageLocale = locale ?? Locale(identifier:
            SystemLanguageResolverV1(bundle: bundle).resolve().effectiveLanguage.rawValue)
        return BundledLocalizationCatalogV1.syncStateLocalized(
            key, bundle: bundle, locale: languageLocale
        )
    }
}

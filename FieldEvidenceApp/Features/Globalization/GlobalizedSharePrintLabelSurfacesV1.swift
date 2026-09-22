import Foundation

/// App-owned presentation only. System share/mail/print controls stay with iOS;
/// none of these strings translate or regenerate an attached document.
struct GlobalizedSharePrintLabelSurfacesV1 {
    let bundle: Bundle
    let appLanguage: AppLanguageTagV1
    var languageLocale: Locale { Locale(identifier: appLanguage.rawValue) }

    init(bundle: Bundle = .main, appLanguage: AppLanguageTagV1? = nil) {
        self.bundle = bundle
        self.appLanguage = appLanguage ?? SystemLanguageResolverV1(bundle: bundle).resolve().effectiveLanguage
    }

    var shareOrPrint: String {
        String(localized: "v30.share.action.share-or-print", defaultValue: "Share or print PDF",
               bundle: bundle, locale: languageLocale,
               comment: "Report action opening the existing iOS share sheet, which includes printing when available. No completion claim.")
    }

    func reportSubject(title: String) -> String {
        let template = String(localized: "v30.share.report.subject", defaultValue: "Report: %@",
                              bundle: bundle, locale: languageLocale,
                              comment: "Share/email subject. One argument: the verbatim authored report title; do not translate the argument.")
        return String(format: template, locale: languageLocale, title)
    }

    func reportBody(title: String, subtitle: String, documentLanguage: String) -> String {
        let template = String(localized: "v30.share.report.body", defaultValue: "%1$@\n%2$@\n\n%3$@",
                              bundle: bundle, locale: languageLocale,
                              comment: "Share/email summary. Arguments: verbatim authored title, verbatim site name, localized document-language disclosure. Attachment contents remain unchanged.")
        return String(format: template, locale: languageLocale, title, subtitle, documentLanguage)
    }

    func documentLanguage(_ selection: ReportLanguageSelectionV1?) -> String {
        guard let selection else {
            return String(localized: "v30.share.document-language.unrecorded",
                          defaultValue: "Document language was not recorded. The saved document is unchanged.",
                          bundle: bundle, locale: languageLocale,
                          comment: "Historic PDF without recorded document language. Never infer its language from current app preferences.")
        }
        let effective = languageName(selection.effectiveLanguage)
        if selection.fallback == .englishWithUserConfirmation {
            let template = String(localized: "v30.share.document-language.fallback",
                                  defaultValue: "Document language: %1$@ (requested %2$@; English fallback confirmed).",
                                  bundle: bundle, locale: languageLocale,
                                  comment: "Frozen document language. Arguments: effective language, requested language. Confirmation belongs to original generation, not current sharing.")
            return String(format: template, locale: languageLocale, effective, languageName(selection.requestedLanguage))
        }
        let template = String(localized: "v30.share.document-language.exact", defaultValue: "Document language: %@.",
                              bundle: bundle, locale: languageLocale,
                              comment: "Language of document chrome, not a claim about the language of authored content. Argument is a localized language name.")
        return String(format: template, locale: languageLocale, effective)
    }

    private func languageName(_ language: AppLanguageTagV1) -> String {
        languageLocale.localizedString(forIdentifier: language.rawValue) ?? language.rawValue
    }

    func audience(_ audience: ReportAudienceV1) -> String {
        switch audience {
        case .internalUse:
            return String(localized: "v30.share.audience.internal", defaultValue: "Internal use", bundle: bundle,
                          locale: languageLocale, comment: "Open-evidence handoff audience label; never changes the selected audience.")
        case .customerSafe:
            return String(localized: "v30.share.audience.customer-safe", defaultValue: "Customer-safe", bundle: bundle,
                          locale: languageLocale, comment: "Open-evidence handoff audience label; not an independent privacy assessment.")
        }
    }

    var feedbackSubject: String {
        String(localized: "feedback.mail.subject", defaultValue: "App feedback", bundle: bundle,
               locale: languageLocale, comment: "Subject of the support email.")
    }

    func feedbackBody(version: String, build: String, device: String, os: String) -> String {
        let template = String(localized: "feedback.mail.body_template",
                              defaultValue: "App version: %@ (%@)\nDevice: %@\nOS: iOS %@\n\nFeedback:\n",
                              bundle: bundle, locale: languageLocale,
                              comment: "Editable support-email body. Arguments are app version, build, device model, and OS version.")
        return String(format: template, locale: languageLocale, version, build, device, os)
    }

    /// Label document chrome is English in the frozen renderer. These are the
    /// independently localized controls/status surrounding its immutable output.
    func label(_ key: AssetLabelLocalizationKeyV1) -> String {
        String(localized: key.rawValue,
               defaultValue: BundledLocalizationCatalogV1.assetLabelEnglish(key),
               bundle: bundle, locale: languageLocale,
               comment: "Asset label output controls/status; generation and system handoff never confirm printing, delivery, affixing, or a physical scan.")
    }

    var doNotDeploy: String {
        String(localized: "v30.share.labels.do-not-deploy",
               defaultValue: "Historic output: do not deploy retired or replaced labels.",
               bundle: bundle, locale: languageLocale,
               comment: "Mandatory warning accompanying non-current label exports. Does not claim permission to reprint or deploy.")
    }
}

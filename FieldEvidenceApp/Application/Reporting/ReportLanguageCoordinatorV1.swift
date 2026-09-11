import Foundation

/// Device-local report choice. There is no app-language override, jurisdiction
/// writer, authored-content translation, or canonical report mutation here.
@MainActor
struct ReportLanguageCoordinatorV1 {
    private let preferences: any GlobalizationPresentationPreferencesPortV1

    init(preferences: any GlobalizationPresentationPreferencesPortV1 = PreferencesAdapterV1()) {
        self.preferences = preferences
    }

    func loadPreference() throws -> GlobalizationPresentationPreferenceV1 {
        let value = try preferences.readGlobalizationPresentationPreference()
        try value.validate()
        return value
    }

    func requestedLanguage(
        preference: GlobalizationPresentationPreferenceV1,
        effectiveAppLanguage: AppLanguageTagV1
    ) -> AppLanguageTagV1 {
        preference.reportLanguage?.requestedLanguage ?? effectiveAppLanguage
    }

    func resolve(
        requested: AppLanguageTagV1, confirmsEnglishFallback: Bool = false
    ) throws -> ReportLanguageSelectionV1 {
        try ReportLanguageControlPolicyV1.resolve(
            requested: requested, confirmsEnglishFallback: confirmsEnglishFallback
        )
    }

    @discardableResult
    func save(
        requested: AppLanguageTagV1, confirmsEnglishFallback: Bool = false, operationID: UUID
    ) throws -> GlobalizationPresentationPreferenceV1 {
        let selection = try resolve(requested: requested, confirmsEnglishFallback: confirmsEnglishFallback)
        return try preferences.updateGlobalizationReportLanguage(selection, operationID: operationID)
    }

    @discardableResult
    func useAppLanguageDefault(operationID: UUID) throws -> GlobalizationPresentationPreferenceV1 {
        try preferences.updateGlobalizationReportLanguage(nil, operationID: operationID)
    }

    /// Captures an explicit choice before rendering. A saved, confirmed English
    /// fallback remains valid on relaunch; an unresolved app-language default
    /// requires confirmation instead of silently falling back.
    func makeRenderRequest(
        effectiveAppLanguage: AppLanguageTagV1, confirmsEnglishFallback: Bool = false
    ) throws -> ReportLanguageRenderRequestV1 {
        let preference = try loadPreference()
        let selection: ReportLanguageSelectionV1
        if let saved = preference.reportLanguage {
            try ReportLanguageControlPolicyV1.validateForCurrentRenderer(saved)
            selection = saved
        } else {
            selection = try resolve(
                requested: effectiveAppLanguage, confirmsEnglishFallback: confirmsEnglishFallback
            )
        }
        return try .init(selection: selection, requestedFormatting: preference.formatting)
    }
}

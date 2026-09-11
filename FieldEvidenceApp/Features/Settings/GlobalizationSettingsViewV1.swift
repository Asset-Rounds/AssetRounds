import Foundation
import SwiftUI

/// A device-local presentation surface. iOS owns app-language selection; this
/// view can only request a separately persisted report-language preference.
struct GlobalizationSettingsViewV1: View {
    static let screenAccessibilityIdentifier = "v30.language-region.screen"
    static let effectiveLanguageAccessibilityIdentifier = "v30.language-region.effective-language"
    static let formattingRegionAccessibilityIdentifier = "v30.language-region.formatting-region"
    static let openSettingsAccessibilityIdentifier = "v30.language-region.open-settings"
    static let reportPickerAccessibilityIdentifier = "v30.language-region.report-language-picker"
    static let reportRequestedAccessibilityIdentifier = "v30.language-region.report-requested"
    static let reportEffectiveAccessibilityIdentifier = "v30.language-region.report-effective"
    static let reportErrorAccessibilityIdentifier = "v30.language-region.report-error"

    @Environment(\.scenePhase) private var scenePhase
    @State private var effectiveLanguage = SystemLanguageResolverV1().resolve()
    @State private var preference: GlobalizationPresentationPreferenceV1?
    @State private var selectedRequestedLanguage: AppLanguageTagV1 = .english
    @State private var isPreferenceAvailable = false
    @State private var settingsUnavailable = false
    @State private var changeError: String?
    @State private var pendingEnglishFallbackLanguage: AppLanguageTagV1?
    @State private var showsEnglishFallbackConfirmation = false
    private enum ErrorFocus: Hashable { case systemSettings, reportLanguage }
    @AccessibilityFocusState private var errorFocus: ErrorFocus?

    private let reportCoordinator: ReportLanguageCoordinatorV1
    private let systemSettings: any GlobalizationSystemSettingsPortV1

    init(
        reportCoordinator: ReportLanguageCoordinatorV1 = ReportLanguageCoordinatorV1(),
        systemSettings: any GlobalizationSystemSettingsPortV1 = GlobalizationSettingsCoordinatorV1()
    ) {
        self.reportCoordinator = reportCoordinator
        self.systemSettings = systemSettings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    sectionHeading(BundledLocalizationCatalogV1.v30Text(.shellLanguageAndRegionHeading))
                    valueRow(
                        GlobalizationSettingsLocalizationKeyV1.effectiveAppLanguage,
                        value: displayLanguage(effectiveLanguage.effectiveLanguage)
                    )
                    .accessibilityIdentifier(Self.effectiveLanguageAccessibilityIdentifier)
                    valueRow(
                        GlobalizationSettingsLocalizationKeyV1.formattingRegion,
                        value: displayFormattingRegion
                    )
                    .accessibilityIdentifier(Self.formattingRegionAccessibilityIdentifier)
                    Text(BundledLocalizationCatalogV1.v30Text(.shellLanguageAndRegionJurisdictionNotice))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(localized(.jurisdictionBoundaryNotice))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(BundledLocalizationCatalogV1.v30Text(.shellLanguageSupportDetails)) {
                        languageSupportCopy
                        Text(BundledLocalizationCatalogV1.v30Text(.shellLanguageSupportPrivacyNotice))
                            .font(.footnote)
                    }
                    .accessibilityIdentifier("v30.language-region.support-summary")

                    Button(BundledLocalizationCatalogV1.v30Text(.shellOpenSystemSettings)) {
                        Task {
                            settingsUnavailable = !(await systemSettings.openAppSettings())
                            if settingsUnavailable {
                                DispatchQueue.main.async {
                                    errorFocus = .systemSettings
                                }
                            }
                        }
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityIdentifier(Self.openSettingsAccessibilityIdentifier)
                    if settingsUnavailable {
                        Text(BundledLocalizationCatalogV1.v30Text(.shellSystemSettingsUnavailable))
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.blockedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($errorFocus, equals: .systemSettings)
                    }
                }

                WorklightCard {
                    sectionHeading(localized(.reportLanguage))
                    Text(localized(.currentPDFEnglishOnly))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker(localized(.reportLanguage), selection: reportLanguageBinding) {
                        ForEach(ReportLanguageControlPolicyV1.requestableLanguages, id: \.self) { language in
                            Text(displayLanguage(language)).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: DesignTokens.Control.minimumHitSize, alignment: .leading)
                    .disabled(!isPreferenceAvailable)
                    .accessibilityIdentifier(Self.reportPickerAccessibilityIdentifier)

                    valueRow(
                        GlobalizationSettingsLocalizationKeyV1.requestedReportLanguage,
                        value: isPreferenceAvailable
                            ? displayLanguage(selectedRequestedLanguage)
                            : localized(.reportLanguageUnavailable)
                    )
                    .accessibilityIdentifier(Self.reportRequestedAccessibilityIdentifier)
                    valueRow(
                        GlobalizationSettingsLocalizationKeyV1.effectiveReportLanguage,
                        value: effectiveReportLanguageDisplay
                    )
                    .accessibilityIdentifier(Self.reportEffectiveAccessibilityIdentifier)

                    Button(localized(.useAppLanguage)) {
                        useAppLanguageDefault()
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .disabled(!isPreferenceAvailable)
                    .accessibilityIdentifier("v30.language-region.use-app-language")

                    if reportLanguageRequiresEnglishConfirmation {
                        Button(localized(.englishFallbackConfirmationAction)) {
                            requestEnglishFallbackConfirmation()
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .frame(minHeight: DesignTokens.Control.minimumHitSize)
                        .disabled(!isPreferenceAvailable)
                        .accessibilityIdentifier("v30.language-region.confirm-english-fallback")
                    }

                    Text(localized(.frozenReportsNotice))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(localized(.authoredContentNotice))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let changeError {
                        Text(changeError)
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.blockedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($errorFocus, equals: .reportLanguage)
                            .accessibilityIdentifier(Self.reportErrorAccessibilityIdentifier)
                    }
                }
            }
            .padding(DesignTokens.Spacing.medium)
            .modifier(GlobalizationAdaptiveLayoutPolicyV1())
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.shellLanguageAndRegionHeading))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refresh()
            }
        }
        .alert(
            localized(.englishFallbackConfirmationTitle),
            isPresented: $showsEnglishFallbackConfirmation
        ) {
            Button(localized(.cancel), role: .cancel) {
                pendingEnglishFallbackLanguage = nil
            }
            Button(localized(.englishFallbackConfirmationAction)) {
                if let language = pendingEnglishFallbackLanguage {
                    save(language, confirmsEnglishFallback: true)
                }
                pendingEnglishFallbackLanguage = nil
            }
        } message: {
            Text(localized(.englishFallbackConfirmationMessage))
        }
    }

    private var reportLanguageBinding: Binding<AppLanguageTagV1> {
        Binding(
            get: { selectedRequestedLanguage },
            set: { selectReportLanguage($0) }
        )
    }

    @ViewBuilder
    private var languageSupportCopy: some View {
        if let diagnostic = effectiveLanguage.fallbackDiagnostic {
            Text(BundledLocalizationCatalogV1.v30Text(
                diagnostic.usedEnglishFallback
                    ? .shellEnglishFallbackExplanation
                    : .shellBaseLanguageFallbackExplanation
            ))
        } else {
            Text(BundledLocalizationCatalogV1.v30Text(.shellSystemLanguageExplanation))
        }
    }

    private var displayFormattingRegion: String {
        let deviceLocale = Locale.autoupdatingCurrent
        let presentationLocale = displayLocale
        let region = deviceLocale.regionCode.flatMap { presentationLocale.localizedString(forRegionCode: $0) }
        return GlobalizationRTLSemanticsV1.opaqueFallback(region, identifier: deviceLocale.identifier)
    }

    private var effectiveReportLanguageDisplay: String {
        guard isPreferenceAvailable else { return localized(.reportLanguageUnavailable) }
        if let selection = preference?.reportLanguage {
            guard (try? ReportLanguageControlPolicyV1.validateForCurrentRenderer(selection)) != nil else {
                return localized(.reportLanguageUnavailable)
            }
            return displayLanguage(selection.effectiveLanguage)
        }
        if let selection = try? reportCoordinator.resolve(requested: selectedRequestedLanguage) {
            return displayLanguage(selection.effectiveLanguage)
        }
        return localized(.confirmationRequired)
    }

    private var reportLanguageRequiresEnglishConfirmation: Bool {
        guard isPreferenceAvailable else { return false }
        if let selection = preference?.reportLanguage {
            return (try? ReportLanguageControlPolicyV1.validateForCurrentRenderer(selection)) == nil
        }
        do {
            _ = try reportCoordinator.resolve(requested: selectedRequestedLanguage)
            return false
        } catch ReportLanguageControlFailureV1.englishConfirmationRequired {
            return true
        } catch {
            return false
        }
    }

    private var displayLocale: Locale {
        Locale(identifier: effectiveLanguage.effectiveLanguage.rawValue)
    }

    private func localized(_ key: GlobalizationSettingsLocalizationKeyV1) -> String {
        BundledLocalizationCatalogV1.globalizationSettingsLocalized(key, locale: displayLocale)
    }

    private func sectionHeading(_ value: String) -> some View {
        Text(value)
            .font(.title2.weight(.bold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func valueRow(
        _ key: GlobalizationSettingsLocalizationKeyV1,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(localized(key))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func displayLanguage(_ language: AppLanguageTagV1) -> String {
        GlobalizationRTLSemanticsV1.opaqueFallback(
            displayLocale.localizedString(forIdentifier: language.rawValue),
            identifier: language.rawValue
        )
    }

    private func refresh() {
        pendingEnglishFallbackLanguage = nil
        showsEnglishFallbackConfirmation = false
        effectiveLanguage = GlobalizationSettingsCoordinatorV1().refreshEffectiveLanguage()
        settingsUnavailable = false
        do {
            let loadedPreference = try reportCoordinator.loadPreference()
            preference = loadedPreference
            selectedRequestedLanguage = reportCoordinator.requestedLanguage(
                preference: loadedPreference,
                effectiveAppLanguage: effectiveLanguage.effectiveLanguage
            )
            isPreferenceAvailable = true
            changeError = nil
        } catch {
            preference = nil
            selectedRequestedLanguage = effectiveLanguage.effectiveLanguage
            isPreferenceAvailable = false
            presentError(localized(.preferenceUnavailable))
        }
    }

    private func selectReportLanguage(_ requested: AppLanguageTagV1) {
        guard isPreferenceAvailable else { return }
        if requested == selectedRequestedLanguage,
           let selection = preference?.reportLanguage,
           (try? ReportLanguageControlPolicyV1.validateForCurrentRenderer(selection)) != nil {
            return
        }
        do {
            _ = try reportCoordinator.resolve(requested: requested)
            save(requested, confirmsEnglishFallback: false)
        } catch ReportLanguageControlFailureV1.englishConfirmationRequired {
            pendingEnglishFallbackLanguage = requested
            showsEnglishFallbackConfirmation = true
        } catch {
            presentError(localized(.selectionSaveFailed))
        }
    }

    private func requestEnglishFallbackConfirmation() {
        guard isPreferenceAvailable else { return }
        pendingEnglishFallbackLanguage = selectedRequestedLanguage
        showsEnglishFallbackConfirmation = true
    }

    private func save(_ requested: AppLanguageTagV1, confirmsEnglishFallback: Bool) {
        do {
            let saved = try reportCoordinator.save(
                requested: requested,
                confirmsEnglishFallback: confirmsEnglishFallback,
                operationID: UUID()
            )
            preference = saved
            selectedRequestedLanguage = requested
            changeError = nil
        } catch {
            presentError(localized(.selectionSaveFailed))
        }
    }

    private func useAppLanguageDefault() {
        guard isPreferenceAvailable else { return }
        do {
            let saved = try reportCoordinator.useAppLanguageDefault(operationID: UUID())
            preference = saved
            selectedRequestedLanguage = effectiveLanguage.effectiveLanguage
            changeError = nil
        } catch {
            presentError(localized(.selectionSaveFailed))
        }
    }

    private func presentError(_ value: String) {
        changeError = value
        focusError()
    }

    private func focusError() {
        DispatchQueue.main.async {
            errorFocus = .reportLanguage
        }
    }
}

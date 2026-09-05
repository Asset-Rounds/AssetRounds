import Foundation

/// Public-API adapter for iOS device and per-app language resolution. It does
/// not mutate Bundle state, install overrides, or retain raw preferences.
struct SystemLanguageResolverV1 {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func resolve() -> EffectiveLanguageResolutionV1 {
        resolve(
            observedLocalizationIdentifiers: bundle.preferredLocalizations,
            preferredLanguageIdentifiers: Locale.preferredLanguages,
            declaredLocalizationIdentifiers: bundle.localizations
        )
    }

    /// Keep iOS's effective resource observation separate from the preference
    /// evidence: prepending that resource would hide every English fallback.
    func resolve(
        observedLocalizationIdentifiers: [String],
        preferredLanguageIdentifiers: [String],
        declaredLocalizationIdentifiers: [String]
    ) -> EffectiveLanguageResolutionV1 {
        let declared = Self.uniqueDeclaredResources(declaredLocalizationIdentifiers)
        guard let observed = observedLocalizationIdentifiers.first,
              declared.contains(observed), let language = Self.appLanguage(for: observed) else {
            return resolve(preferredLanguageIdentifiers: preferredLanguageIdentifiers,
                           declaredLocalizationIdentifiers: declared)
        }
        let inferred = Self.provenance(selectedResource: observed,
                                       preferredLanguageIdentifiers: preferredLanguageIdentifiers)
        return EffectiveLanguageResolutionV1(
            effectiveLanguage: language,
            resourceIdentifier: observed,
            provenance: inferred == .englishFallback && language != .english
                ? .systemSelectedResource : inferred
        )
    }

    /// Injectable inputs keep the fallback chain deterministic in tests while
    /// production callers use `resolve()` and Apple's Bundle API.
    func resolve(
        preferredLanguageIdentifiers: [String],
        declaredLocalizationIdentifiers: [String]
    ) -> EffectiveLanguageResolutionV1 {
        let declared = Self.uniqueDeclaredResources(declaredLocalizationIdentifiers)
        for preference in preferredLanguageIdentifiers {
            let compatible = declared.filter {
                Self.baseLanguage($0) == Self.baseLanguage(preference)
                    && Self.scriptsAreCompatible($0, preference)
                    && Self.appLanguage(for: $0) != nil
            }
            let applePreferred = Bundle.preferredLocalizations(
                from: compatible,
                forPreferences: [preference]
            )
            if let selected = applePreferred.first,
               compatible.contains(selected),
               let language = Self.appLanguage(for: selected) {
                return EffectiveLanguageResolutionV1(
                    effectiveLanguage: language,
                    resourceIdentifier: selected,
                    provenance: Self.provenance(
                        selectedResource: selected,
                        preferredLanguageIdentifiers: [preference]
                    )
                )
            }
        }

        if let english = Self.englishResource(in: declared) {
            return EffectiveLanguageResolutionV1(
                effectiveLanguage: .english,
                resourceIdentifier: english,
                provenance: .englishFallback
            )
        }
        return EffectiveLanguageResolutionV1(
            effectiveLanguage: .english,
            resourceIdentifier: nil,
            provenance: .englishFallback
        )
    }

    private static func uniqueDeclaredResources(_ identifiers: [String]) -> [String] {
        Array(Set(identifiers.filter { !$0.isEmpty })).sorted()
    }

    private static func provenance(
        selectedResource: String,
        preferredLanguageIdentifiers: [String]
    ) -> EffectiveLanguageResourceProvenanceV1 {
        if preferredLanguageIdentifiers.contains(where: {
            normalized($0) == normalized(selectedResource)
        }) {
            return .exactDeclaredResource
        }
        if preferredLanguageIdentifiers.contains(where: {
            baseLanguage($0) == baseLanguage(selectedResource)
        }) {
            return .baseLanguageResource
        }
        return .englishFallback
    }

    private static func englishResource(in declared: [String]) -> String? {
        declared.first(where: { normalized($0) == "en" })
            ?? declared.first(where: { baseLanguage($0) == "en" })
    }

    private static func appLanguage(for resourceIdentifier: String) -> AppLanguageTagV1? {
        let normalizedResource = normalized(resourceIdentifier)
        let candidates = AppLanguageTagV1.supportedRawValues.sorted {
            $0.count > $1.count
        }
        guard let match = candidates.first(where: {
            let normalizedCandidate = normalized($0)
            return normalizedResource == normalizedCandidate
                || normalizedResource.hasPrefix(normalizedCandidate + "-")
        }) else {
            return nil
        }
        return try? AppLanguageTagV1(match)
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func scriptsAreCompatible(_ resource: String, _ preference: String) -> Bool {
        func script(_ value: String) -> Substring? {
            guard let subtag = normalized(value).split(separator: "-").dropFirst().first,
                  subtag.count == 4, subtag.allSatisfy(\.isLetter) else { return nil }
            return subtag
        }
        guard let resourceScript = script(resource), let preferredScript = script(preference) else {
            return true
        }
        return resourceScript == preferredScript
    }

    private static func baseLanguage(_ identifier: String) -> String {
        normalized(identifier).split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
    }
}

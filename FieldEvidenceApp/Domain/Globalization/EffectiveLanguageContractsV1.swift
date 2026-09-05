import Foundation

/// The source of the resource iOS selected for the current app language.
/// This is presentation evidence only and never workspace or report truth.
enum EffectiveLanguageResourceProvenanceV1: String, Codable, Equatable, Sendable {
    case exactDeclaredResource = "EXACT_DECLARED_RESOURCE"
    case baseLanguageResource = "BASE_LANGUAGE_RESOURCE"
    case englishFallback = "ENGLISH_FALLBACK"
}

/// A privacy-safe locally inspectable fallback summary. It deliberately does
/// not retain the person's preferred-language list or any localized key.
struct EffectiveLanguageFallbackDiagnosticV1: Codable, Equatable, Sendable {
    let provenance: EffectiveLanguageResourceProvenanceV1
    let usedEnglishFallback: Bool

    init(provenance: EffectiveLanguageResourceProvenanceV1) {
        self.provenance = provenance
        usedEnglishFallback = provenance == .englishFallback
    }
}

/// The language and declared bundle resource currently effective for app UI.
/// `resourceIdentifier` is app-bundled resource provenance, never user input.
struct EffectiveLanguageResolutionV1: Codable, Equatable, Sendable {
    let effectiveLanguage: AppLanguageTagV1
    let resourceIdentifier: String?
    let provenance: EffectiveLanguageResourceProvenanceV1
    let fallbackDiagnostic: EffectiveLanguageFallbackDiagnosticV1?

    init(
        effectiveLanguage: AppLanguageTagV1,
        resourceIdentifier: String?,
        provenance: EffectiveLanguageResourceProvenanceV1
    ) {
        self.effectiveLanguage = effectiveLanguage
        self.resourceIdentifier = resourceIdentifier
        self.provenance = provenance
        fallbackDiagnostic = provenance == .exactDeclaredResource
            ? nil
            : EffectiveLanguageFallbackDiagnosticV1(provenance: provenance)
    }
}

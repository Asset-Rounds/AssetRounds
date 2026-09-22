import Foundation

/// Locale resource availability and localized labels are deliberately not inputs.
/// Every operation re-probes; this value never caches availability or grants
/// permission, activation, canonical write authority, or a cloud fallback.
enum AssistedInputCapabilityCoordinatorV1 {
    static func evaluate(
        query: AssistedInputCapabilityQueryV1,
        observation: AssistedInputCapabilityObservationV1?,
        currentEnvironment: AssistedInputEnvironmentV1,
        featureEnabled: Bool
    ) -> AssistedInputCapabilityDispositionV1 {
        guard featureEnabled else { return .featureDisabled }
        guard let observation else { return .unobserved }
        guard observation.query == query, query.environment == currentEnvironment else { return .staleObservation }
        guard Set(query.localeIdentifiers).isSubset(of: Set(observation.supportedLocaleIdentifiers)) else {
            return .unsupportedLocale
        }
        if observation.onDevice == .available { return .availableOnDevice }
        if observation.onDevice == .unobserved { return .unobserved }
        if observation.online == .available { return .onlineOnly }
        return .unavailable
    }
}

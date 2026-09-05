import Foundation
import UIKit

/// Public system Settings handoff. iOS owns the per-app language choice.
@MainActor
struct GlobalizationSettingsCoordinatorV1: GlobalizationSystemSettingsPortV1 {
    func refreshEffectiveLanguage(
        preferences: PreferencesAdapterV1 = PreferencesAdapterV1()
    ) -> EffectiveLanguageResolutionV1 {
        let result = SystemLanguageResolverV1().resolve()
        // Diagnostics are best-effort device-local support data. A storage
        // failure must not prevent the system-selected language from loading.
        try? preferences.recordGlobalizationFallback(result.fallbackDiagnostic)
        return result
    }

    func openAppSettings() async -> Bool {
        guard let destination = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(destination) else {
            return false
        }
        return await UIApplication.shared.open(destination, options: [:])
    }
}

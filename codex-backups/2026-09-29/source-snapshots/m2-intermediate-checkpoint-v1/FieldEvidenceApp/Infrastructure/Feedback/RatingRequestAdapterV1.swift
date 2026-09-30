import StoreKit
import UIKit

/// Scene-bound, device-local bridge for the system-owned review consideration.
/// It neither knows nor records whether the system displays a prompt or whether
/// a customer rates, reviews, submits, or takes any other follow-on action.
@MainActor
final class AppStoreRatingRequestAdapterV1: RatingRequestAdapterV1 {
    typealias ActiveWindowSceneProvider = @MainActor () -> UIWindowScene?

    private let activeWindowSceneProvider: ActiveWindowSceneProvider

    /// Production composition uses the deterministically ordered active scene.
    convenience init() {
        self.init(activeWindowSceneProvider: Self.foregroundActiveWindowScene)
    }

    /// Composition and tests inject the exact scene source; the adapter never
    /// chooses a window from a manual Rate control or from a background scene.
    init(activeWindowSceneProvider: @escaping ActiveWindowSceneProvider) {
        self.activeWindowSceneProvider = activeWindowSceneProvider
    }

    /// A fixed scene makes platform/scene availability deterministic in tests.
    convenience init(activeWindowScene: UIWindowScene?) {
        self.init(activeWindowSceneProvider: { activeWindowScene })
    }

    var availability: RatingNativeRequestAvailabilityV1 {
        guard #available(iOS 18.0, *) else {
            return .disabledUnverifiedPlatform
        }
        return activeWindowSceneProvider() == nil ? .sceneUnavailable : .available
    }

    func prepareRequest() -> RatingNativeRequestPreparationV1? {
        guard #available(iOS 18.0, *),
              let scene = activeWindowSceneProvider() else {
            return nil
        }
        return RatingNativeRequestPreparationV1 {
            AppStore.requestReview(in: scene)
            return .systemConsiderationRequested
        }
    }

    private static func foregroundActiveWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .sorted { $0.session.persistentIdentifier < $1.session.persistentIdentifier }
            .first
    }
}

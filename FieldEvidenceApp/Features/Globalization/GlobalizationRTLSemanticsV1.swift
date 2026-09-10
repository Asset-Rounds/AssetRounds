import Foundation

/// Display boundaries for the existing semantic SwiftUI shell. TabView,
/// NavigationStack, Label and leading/trailing alignment remain responsible
/// for native mirroring and logical focus order; source collections and
/// nondirectional artwork are never reversed here.
enum GlobalizationRTLSemanticsV1 {
    static func opaqueFallback(_ localizedName: String?, identifier: String) -> String {
        localizedName ?? BidirectionalTextSafetyV1.opaqueToken(identifier)
    }

    /// The surrounding localized status sentence keeps its own direction even
    /// when the dynamic detail contains mixed text or a hostile bidi control.
    static func accessibilityDetail(_ value: String) -> String {
        BidirectionalTextSafetyV1.naturalText(value)
    }
}

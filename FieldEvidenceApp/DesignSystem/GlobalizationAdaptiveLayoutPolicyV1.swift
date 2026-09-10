import SwiftUI

/// Let localized control text grow vertically at its semantic system font
/// size. Font fallback stays with SwiftUI; this policy never shrinks text,
/// caps Dynamic Type, changes source text, or loads a bundled typeface.
struct GlobalizationAdaptiveLayoutPolicyV1: ViewModifier {
    func body(content: Content) -> some View {
        content
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

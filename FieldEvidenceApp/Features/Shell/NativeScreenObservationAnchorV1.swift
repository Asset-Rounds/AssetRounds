#if DEBUG
import SwiftUI
import UIKit

/// A host-unit mounting witness, not an exported accessibility element.
/// It owns no source, navigation state or callbacks and disappears in Release.
@MainActor
struct NativeScreenObservationAnchorV1: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> NativeScreenObservationViewV1 {
        let view = NativeScreenObservationViewV1()
        view.observationIdentifier = identifier
        return view
    }

    func updateUIView(_ view: NativeScreenObservationViewV1, context: Context) {
        view.observationIdentifier = identifier
    }

    static func dismantleUIView(_ view: NativeScreenObservationViewV1, coordinator: ()) {
        view.observationIdentifier = nil
    }
}

@MainActor
final class NativeScreenObservationViewV1: UIView {
    var observationIdentifier: String?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: CGSize { .zero }
}
#endif

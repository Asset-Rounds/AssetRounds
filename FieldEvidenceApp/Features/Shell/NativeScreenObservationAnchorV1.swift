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
        view.recordLifecycle("make")
        return view
    }

    func updateUIView(_ view: NativeScreenObservationViewV1, context: Context) {
        view.observationIdentifier = identifier
        view.recordLifecycle("update")
    }

    static func dismantleUIView(_ view: NativeScreenObservationViewV1, coordinator: ()) {
        view.recordLifecycle("dismantle")
        view.observationIdentifier = nil
    }
}

@MainActor
final class NativeScreenObservationViewV1: UIView {
    var observationIdentifier: String?
    private var diagnosticEmissionCount = 0

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { return nil }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        recordLifecycle("superview")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        recordLifecycle("window")
    }

    func recordLifecycle(_ phase: String) {
        guard diagnosticEmissionCount < 16 else { return }
        diagnosticEmissionCount += 1
        let windowIdentity = window.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        let parentType = superview.map { String(reflecting: type(of: $0)) } ?? "nil"
        print("NativeWitness phase=\(phase) id=\(observationIdentifier ?? "nil") object=\(ObjectIdentifier(self)) parent=\(parentType) window=\(windowIdentity) hidden=\(isHidden) alpha=\(alpha) frame=\(frame) bounds=\(bounds)")
    }

    override var intrinsicContentSize: CGSize { .zero }
}
#endif

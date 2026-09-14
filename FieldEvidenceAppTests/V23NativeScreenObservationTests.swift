import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23NativeScreenObservationTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testRealSwiftUIBranchMountUnmountAndWindowScope() async throws {
        #if DEBUG
        let model = V23ObservationBranchState()
        let host = UIHostingController(rootView: V23ObservationBranch(model: model, identifier: "ready"))
        let fixture = try V23ObservationWindow(host)
        defer { fixture.close() }
        XCTAssertFalse(nativeScreenObservation("ready", from: host).found)
        model.phase = .failed
        host.view.layoutIfNeeded()
        XCTAssertFalse(nativeScreenObservation("ready", from: host).found)
        model.phase = .ready
        let mounted = await waitForMountedScreen("ready", from: host)
        XCTAssertTrue(mounted)
        XCTAssertFalse(nativeScreenObservation("wrong", from: host).found)
        let other = UIHostingController(rootView: V23ObservationBranch(model: model, identifier: "ready"))
        other.loadViewIfNeeded()
        XCTAssertFalse(nativeScreenObservation("ready", from: other).found)
        host.view.isHidden = true
        XCTAssertFalse(nativeScreenObservation("ready", from: host).found)
        host.view.isHidden = false
        XCTAssertTrue(nativeScreenObservation("ready", from: host).found)
        model.phase = .failed
        let failedUnmount = await waitForUnmount("ready", from: host)
        XCTAssertTrue(failedUnmount)
        model.phase = .ready
        let readyAgain = await waitForMountedScreen("ready", from: host)
        XCTAssertTrue(readyAgain)
        model.phase = .loading
        let unmounted = await waitForUnmount("ready", from: host)
        XCTAssertTrue(unmounted)
        model.phase = .ready
        let remounted = await waitForMountedScreen("ready", from: host)
        XCTAssertTrue(remounted)
        fixture.close()
        XCTAssertFalse(nativeScreenObservation("ready", from: host).found)
        #else
        throw XCTSkip("Native mounting witnesses are DEBUG-only")
        #endif
    }

    @MainActor
    func testSelectedTabAndNativeBackRejectRetainedScreens() async throws {
        #if DEBUG
        let ready = V23ObservationBranchState()
        ready.phase = .ready
        let root = UIHostingController(rootView: V23ObservationBranch(model: ready, identifier: "root"))
        let detail = UIHostingController(rootView: V23ObservationBranch(model: ready, identifier: "detail"))
        let duplicate = UIHostingController(rootView: V23ObservationBranch(model: ready, identifier: "detail"))
        let navigation = UINavigationController(rootViewController: root)
        let otherNavigation = UINavigationController(rootViewController: duplicate)
        let tabs = UITabBarController()
        tabs.viewControllers = [navigation, otherNavigation]
        tabs.selectedIndex = 1
        let fixture = try V23ObservationWindow(tabs)
        defer { fixture.close() }
        let otherMounted = await waitForMountedScreen("detail", from: tabs)
        XCTAssertTrue(otherMounted)
        XCTAssertTrue(nativeScreenObservation("detail", from: tabs).navigation === otherNavigation)
        tabs.selectedIndex = 0
        let rootMounted = await waitForNativeRoot("root", from: tabs)
        XCTAssertTrue(rootMounted)
        XCTAssertFalse(nativeScreenObservation("detail", from: tabs).found)
        navigation.pushViewController(detail, animated: false)
        let detailMounted = await waitForMountedScreen("detail", from: tabs)
        XCTAssertTrue(detailMounted)
        XCTAssertFalse(nativeScreenObservation("root", from: tabs).found)
        let owner = try XCTUnwrap(nativeScreenObservation("detail", from: tabs).navigation)
        XCTAssertTrue(owner === navigation)
        XCTAssertEqual(owner.viewControllers.count, 2)
        owner.popToRootViewController(animated: false)
        let restored = await waitForNativeRoot("root", from: tabs)
        XCTAssertTrue(restored)
        XCTAssertFalse(nativeScreenObservation("detail", from: tabs).found)
        XCTAssertEqual(otherNavigation.viewControllers.count, 1)
        #else
        throw XCTSkip("Native mounting witnesses are DEBUG-only")
        #endif
    }

    @MainActor
    func testPresentedNativeControllerMasksCoveredHostAndDismissalRestoresIt() async throws {
        #if DEBUG
        let ready = V23ObservationBranchState()
        ready.phase = .ready
        let host = UIHostingController(rootView: V23ObservationBranch(model: ready, identifier: "covered"))
        let fixture = try V23ObservationWindow(host)
        defer { fixture.close() }
        let initiallyMounted = await waitForMountedScreen("covered", from: host)
        XCTAssertTrue(initiallyMounted)
        let modal = UIHostingController(rootView: V23ObservationBranch(model: ready, identifier: "modal"))
        let navigation = UINavigationController(rootViewController: modal)
        navigation.modalPresentationStyle = .overFullScreen
        host.present(navigation, animated: false)
        let presented = await waitForMountedScreen("modal", from: host)
        XCTAssertTrue(presented)
        XCTAssertTrue(nativeScreenObservation("modal", from: host).navigation === navigation)
        XCTAssertFalse(nativeScreenObservation("covered", from: host).found)
        host.dismiss(animated: false)
        let restored = await waitForMountedScreen("covered", from: host)
        XCTAssertTrue(restored)
        XCTAssertFalse(nativeScreenObservation("modal", from: host).found)
        #else
        throw XCTSkip("Native mounting witnesses are DEBUG-only")
        #endif
    }

    @MainActor
    func testWitnessHasNoLayoutInteractionOrAccessibilityRoleAndClearsOnDismantle() throws {
        #if DEBUG
        let view = NativeScreenObservationViewV1()
        view.observationIdentifier = "ready"
        XCTAssertEqual(view.intrinsicContentSize, .zero)
        XCTAssertEqual(view.frame, .zero)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertTrue(view.accessibilityElementsHidden)
        XCTAssertNil(view.accessibilityIdentifier)
        XCTAssertNil(view.accessibilityCustomActions)
        NativeScreenObservationAnchorV1.dismantleUIView(view, coordinator: ())
        XCTAssertNil(view.observationIdentifier)
        #else
        throw XCTSkip("Native mounting witnesses are DEBUG-only")
        #endif
    }

    @MainActor
    private func waitForUnmount(_ identifier: String, from host: UIViewController) async -> Bool {
        for _ in 0..<200 {
            if !nativeScreenObservation(identifier, from: host).found { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }
}

#if DEBUG
@MainActor
private final class V23ObservationBranchState: ObservableObject {
    enum Phase { case loading, ready, failed }
    @Published var phase: Phase = .loading
}

@MainActor
private struct V23ObservationBranch: View {
    @ObservedObject var model: V23ObservationBranchState
    let identifier: String

    var body: some View {
        switch model.phase {
        case .loading: ProgressView("Loading")
        case .failed: Text("Unavailable")
        case .ready:
            Text("Ready")
                .background {
                    NativeScreenObservationAnchorV1(identifier: identifier)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                }
        }
    }
}

@MainActor
private final class V23ObservationWindow {
    let window: UIWindow
    let previous: UIWindow?

    init(_ host: UIViewController) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
    }
}
#endif

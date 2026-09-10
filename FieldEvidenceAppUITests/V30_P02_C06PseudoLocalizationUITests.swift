import Foundation
import UIKit
import XCTest

final class V30_P02_C06PseudoLocalizationUITests: XCTestCase {
    private static let harnessArgument = "--v30-p02-c06-harness"
    private static let uiTestingArgument = "--v30-ui-testing"
    private static let expectedCaseIDs = ["C06-UI-01", "C06-UI-02", "C06-UI-03"]
    private static let expectedIdentifier = "FE-0427-2026"
    private static let expectedAuthoredSource =
        "NFD: cafe\u{301} • ZWJ: 👩‍🔧 • CJK: 漢字 • Hangul: 한글 • Arabic: العربية"

    private enum HarnessError: Error {
        case missingElement(String)
        case invalidMatrix(String)
        case unsupportedOrientation(String)
        case orientationNotApplied(String)
    }

    private struct ScreenshotMatrix: Decodable {
        let schemaVersion: Int
        let cardID: String
        let closedCaseIDs: [String]
        let cases: [MatrixCase]
    }

    private struct MatrixCase: Decodable {
        let id: String
        let profile: String
        let dynamicType: String
        let appearance: String
        let contrast: String
        let orientation: String
        let expectedObservedEnvironment: ObservedEnvironment
        let actions: [String]
        let screenshots: [ScreenshotState]
        let runtimeObservationAttachmentName: String
    }

    private struct ObservedEnvironment: Decodable {
        let dynamicType: String
        let layoutDirection: String
        let colorScheme: String
        let contrast: String
    }

    private struct ScreenshotState: Decodable {
        let state: String
        let attachmentName: String
    }

    private struct RuntimeObservation: Encodable {
        struct Geometry: Encodable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }

        struct RequestedConfiguration: Encodable {
            let profile: String
            let dynamicType: String
            let appearance: String
            let contrast: String
            let orientation: String
        }

        let caseID: String
        let appWindowGeometry: Geometry
        let deviceOrientation: String
        let simulatorModel: String?
        let simulatorUDID: String?
        let osVersion: String
        let observedEnvironment: String
        let requestedConfiguration: RequestedConfiguration
        let screenshotAttachmentNames: [String]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testV30P02C06ClosedPseudoLocaleMatrix() throws {
        let matrix = try loadMatrix()
        XCTAssertEqual(matrix.schemaVersion, 1)
        XCTAssertEqual(matrix.cardID, "V30-P02-C06")
        XCTAssertEqual(matrix.closedCaseIDs, Self.expectedCaseIDs)
        XCTAssertEqual(matrix.cases.map(\.id), Self.expectedCaseIDs)
        XCTAssertEqual(Set(matrix.cases.map(\.id)).count, Self.expectedCaseIDs.count)

        for matrixCase in matrix.cases {
            try run(matrixCase)
        }
    }

    @MainActor
    private func run(_ matrixCase: MatrixCase) throws {
        let originalOrientation = XCUIDevice.shared.orientation
        let requestedOrientation = try deviceOrientation(for: matrixCase.orientation)
        XCUIDevice.shared.orientation = requestedOrientation
        try waitForDeviceOrientation(requestedOrientation)

        let app = XCUIApplication()
        defer {
            if app.state != .notRunning {
                app.terminate()
            }
            XCUIDevice.shared.orientation = originalOrientation == .unknown
                ? .portrait
                : originalOrientation
        }

        app.launchArguments = launchArguments(for: matrixCase)
        app.launch()

        let screen = try requireElement("v30.pseudo.screen", in: app)
        let title = try requireElement("v30.pseudo.title", in: app)
        XCTAssertEqual(app.state, .runningForeground)
        let window = try requireWindow(in: app)
        try waitForWindowAspect(window, matching: matrixCase.orientation)
        assertWindowAspect(window.frame, matches: matrixCase.orientation)

        let observedEnvironment = try requireElement(
            "v30.pseudo.observed-environment",
            in: app
        )
        XCTAssertEqual(
            observedEnvironment.label,
            "layoutDirection \(matrixCase.expectedObservedEnvironment.layoutDirection)"
                + " • dynamicType \(matrixCase.expectedObservedEnvironment.dynamicType)"
                + " • colorScheme \(matrixCase.expectedObservedEnvironment.colorScheme)"
                + " • contrast \(matrixCase.expectedObservedEnvironment.contrast)"
        )

        let identifier = try requireElement("v30.pseudo.identifier", in: app)
        XCTAssertEqual(
            removingDirectionalIsolation(identifier.label),
            Self.expectedIdentifier
        )
        let authoredSource = try requireElement("v30.pseudo.authored-source", in: app)
        XCTAssertEqual(Array(authoredSource.label.utf8), Array(Self.expectedAuthoredSource.utf8))

        let primaryAction = try requireElement("v30.pseudo.primary-action", in: app)
        let navigation = try requireElement("v30.pseudo.navigation", in: app)
        let input = try requireElement("v30.pseudo.input", in: app)
        let errorTrigger = try requireElement("v30.pseudo.error-trigger", in: app)
        let unresolvedTrigger = try requireElement("v30.pseudo.unresolved-trigger", in: app)
        let fallbackTrigger = try requireElement("v30.pseudo.fallback-trigger", in: app)
        let reset = try requireElement("v30.pseudo.diagnostics-reset", in: app)
        let finalAction = try requireElement("v30.pseudo.final-action", in: app)
        let diagnostics = try requireElement("v30.pseudo.diagnostics", in: app)

        [
            primaryAction, navigation, input, errorTrigger, unresolvedTrigger,
            fallbackTrigger, reset, finalAction,
        ].forEach { assertReachableControl($0, in: app, window: window) }
        XCTAssertTrue(diagnostics.label.localizedCaseInsensitiveContains("unresolved 0"))
        XCTAssertTrue(diagnostics.label.localizedCaseInsensitiveContains("unexpected fallback 0"))

        var screenshotAttachmentNames: [String] = []
        scroll(title, in: app)
        XCTAssertTrue(title.isHittable)
        try capture(
            state: "baseline",
            in: matrixCase,
            app: app,
            attachmentNames: &screenshotAttachmentNames
        )

        for action in matrixCase.actions {
            switch action {
            case "navigation-round-trip":
                try runNavigation(navigation, screen: screen, in: app, window: window)
            case "input-keyboard":
                try runKeyboard(
                    input,
                    in: app,
                    window: window,
                    matrixCase: matrixCase,
                    attachmentNames: &screenshotAttachmentNames
                )
            case "trigger-error":
                try runError(
                    errorTrigger,
                    in: app,
                    window: window,
                    matrixCase: matrixCase,
                    attachmentNames: &screenshotAttachmentNames
                )
            case "recovery":
                try runRecovery(
                    in: app,
                    window: window,
                    matrixCase: matrixCase,
                    attachmentNames: &screenshotAttachmentNames
                )
            case "unresolved-fallback-and-reset":
                try runDiagnosticProbeAndReset(
                    unresolvedTrigger: unresolvedTrigger,
                    fallbackTrigger: fallbackTrigger,
                    reset: reset,
                    diagnostics: diagnostics,
                    in: app,
                    window: window
                )
            default:
                throw HarnessError.invalidMatrix("Unsupported action \(action)")
            }
        }

        assertReachableControl(primaryAction, in: app, window: window)
        primaryAction.tap()
        _ = try requireElement("v30.pseudo.completion", in: app)
        assertReachableControl(finalAction, in: app, window: window)
        finalAction.tap()
        _ = try requireElement("v30.pseudo.final-completion", in: app)

        XCTAssertEqual(
            screenshotAttachmentNames,
            matrixCase.screenshots.map(\.attachmentName),
            "Each declared screenshot state must be captured exactly once."
        )

        try attachRuntimeObservation(
            for: matrixCase,
            window: window,
            observedEnvironment: observedEnvironment.label,
            screenshotAttachmentNames: screenshotAttachmentNames
        )
    }

    @MainActor
    private func runNavigation(
        _ navigation: XCUIElement,
        screen: XCUIElement,
        in app: XCUIApplication,
        window: XCUIElement
    ) throws {
        assertReachableControl(navigation, in: app, window: window)
        navigation.tap()
        let destination = try requireElement(
            "v30.pseudo.navigation-destination",
            in: app
        )
        let back = app.navigationBars.buttons.firstMatch
        guard back.waitForExistence(timeout: 10) else {
            XCTFail("Navigation did not expose a back control")
            throw HarnessError.missingElement("navigation back control")
        }
        back.tap()
        guard screen.waitForExistence(timeout: 10) else {
            XCTFail("Navigation did not return to the pseudo-localization screen")
            throw HarnessError.missingElement("v30.pseudo.screen after navigation")
        }
        XCTAssertTrue(destination.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func runKeyboard(
        _ input: XCUIElement,
        in app: XCUIApplication,
        window: XCUIElement,
        matrixCase: MatrixCase,
        attachmentNames: inout [String]
    ) throws {
        assertReachableControl(input, in: app, window: window)
        input.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 10) else {
            XCTFail("Editable pseudo-localization input did not present a keyboard")
            throw HarnessError.missingElement("keyboard")
        }
        input.typeText("Asset-203")
        XCTAssertEqual(input.value as? String, "Asset-203")
        try capture(
            state: "keyboard",
            in: matrixCase,
            app: app,
            attachmentNames: &attachmentNames
        )
        let dismiss = try requireElement("v30.pseudo.keyboard-dismiss", in: app)
        dismiss.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func runError(
        _ trigger: XCUIElement,
        in app: XCUIApplication,
        window: XCUIElement,
        matrixCase: MatrixCase,
        attachmentNames: inout [String]
    ) throws {
        assertReachableControl(trigger, in: app, window: window)
        trigger.tap()
        let error = try requireElement("v30.pseudo.error", in: app)
        scroll(error, in: app)
        XCTAssertTrue(error.isHittable)
        XCTAssertFalse(error.label.isEmpty)
        try capture(
            state: "error",
            in: matrixCase,
            app: app,
            attachmentNames: &attachmentNames
        )
    }

    @MainActor
    private func runRecovery(
        in app: XCUIApplication,
        window: XCUIElement,
        matrixCase: MatrixCase,
        attachmentNames: inout [String]
    ) throws {
        let recovery = try requireElement("v30.pseudo.recovery", in: app)
        assertReachableControl(recovery, in: app, window: window)
        recovery.tap()
        let error = element("v30.pseudo.error", in: app)
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        try capture(
            state: "recovery",
            in: matrixCase,
            app: app,
            attachmentNames: &attachmentNames
        )
    }

    @MainActor
    private func runDiagnosticProbeAndReset(
        unresolvedTrigger: XCUIElement,
        fallbackTrigger: XCUIElement,
        reset: XCUIElement,
        diagnostics: XCUIElement,
        in app: XCUIApplication,
        window: XCUIElement
    ) throws {
        assertReachableControl(unresolvedTrigger, in: app, window: window)
        unresolvedTrigger.tap()
        assertDiagnostics(
            diagnostics,
            contains: "unresolved 1",
            timeout: 10
        )
        assertReachableControl(fallbackTrigger, in: app, window: window)
        fallbackTrigger.tap()
        assertDiagnostics(
            diagnostics,
            contains: "unexpected fallback 1",
            timeout: 10
        )
        assertReachableControl(reset, in: app, window: window)
        reset.tap()
        assertDiagnostics(diagnostics, contains: "unresolved 0", timeout: 10)
        assertDiagnostics(
            diagnostics,
            contains: "unexpected fallback 0",
            timeout: 10
        )
    }

    @MainActor
    private func capture(
        state: String,
        in matrixCase: MatrixCase,
        app: XCUIApplication,
        attachmentNames: inout [String]
    ) throws {
        let matching = matrixCase.screenshots.filter { $0.state == state }
        guard matching.count <= 1 else {
            throw HarnessError.invalidMatrix(
                "\(matrixCase.id) declares duplicate \(state) screenshots"
            )
        }
        guard let screenshotState = matching.first else { return }
        guard element("v30.pseudo.screen", in: app).exists else {
            throw HarnessError.missingElement("v30.pseudo.screen before \(state) screenshot")
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = screenshotState.attachmentName
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachmentNames.append(screenshotState.attachmentName)
    }

    @MainActor
    private func attachRuntimeObservation(
        for matrixCase: MatrixCase,
        window: XCUIElement,
        observedEnvironment: String,
        screenshotAttachmentNames: [String]
    ) throws {
        let frame = window.frame
        let environment = ProcessInfo.processInfo.environment
        let observation = RuntimeObservation(
            caseID: matrixCase.id,
            appWindowGeometry: .init(
                x: Double(frame.origin.x),
                y: Double(frame.origin.y),
                width: Double(frame.width),
                height: Double(frame.height)
            ),
            deviceOrientation: String(describing: XCUIDevice.shared.orientation),
            simulatorModel: nonEmpty(environment["SIMULATOR_MODEL_IDENTIFIER"]),
            simulatorUDID: nonEmpty(environment["SIMULATOR_UDID"]),
            osVersion: UIDevice.current.systemVersion,
            observedEnvironment: observedEnvironment,
            requestedConfiguration: .init(
                profile: matrixCase.profile,
                dynamicType: matrixCase.dynamicType,
                appearance: matrixCase.appearance,
                contrast: matrixCase.contrast,
                orientation: matrixCase.orientation
            ),
            screenshotAttachmentNames: screenshotAttachmentNames
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(
            string: String(decoding: try encoder.encode(observation), as: UTF8.self)
        )
        attachment.name = matrixCase.runtimeObservationAttachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func assertReachableControl(
        _ control: XCUIElement,
        in app: XCUIApplication,
        window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        scroll(control, in: app)
        XCTAssertTrue(control.isHittable, file: file, line: line)
        let visibleWindow = window.frame.insetBy(dx: 1, dy: 1)
        XCTAssertGreaterThanOrEqual(control.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.minX, visibleWindow.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(control.frame.maxX, visibleWindow.maxX, file: file, line: line)
        XCTAssertTrue(control.frame.intersects(visibleWindow), file: file, line: line)
    }

    @MainActor
    private func assertDiagnostics(
        _ diagnostics: XCUIElement,
        contains text: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: diagnostics)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Diagnostics did not contain \(text): \(diagnostics.label)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func requireElement(
        _ identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) throws -> XCUIElement {
        let value = element(identifier, in: app)
        guard value.waitForExistence(timeout: timeout) else {
            XCTFail("Missing required pseudo-localization element: \(identifier)")
            throw HarnessError.missingElement(identifier)
        }
        return value
    }

    @MainActor
    private func requireWindow(in app: XCUIApplication) throws -> XCUIElement {
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 15) else {
            XCTFail("Missing application window")
            throw HarnessError.missingElement("application window")
        }
        return window
    }

    private func loadMatrix() throws -> ScreenshotMatrix {
        let resourceName = "pseudo-locale-screenshot-matrix-v1"
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/PseudoLocalization/\(resourceName).json")
        let bundledURL = Bundle(for: Self.self).url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: "Fixtures/V30/PseudoLocalization"
        )
        let url = bundledURL ?? sourceURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HarnessError.invalidMatrix("Missing screenshot matrix at \(url.path)")
        }
        return try JSONDecoder().decode(ScreenshotMatrix.self, from: Data(contentsOf: url))
    }

    private func launchArguments(for matrixCase: MatrixCase) -> [String] {
        [
            Self.harnessArgument,
            Self.uiTestingArgument,
            "--v30-p02-c06-profile", matrixCase.profile,
            "--v30-p02-c06-dynamic-type", matrixCase.dynamicType,
            "--v30-p02-c06-appearance", matrixCase.appearance,
            "--v30-p02-c06-contrast", matrixCase.contrast,
            "-UIPreferredContentSizeCategoryName",
            matrixCase.dynamicType == "accessibility5"
                ? "UICTContentSizeCategoryAccessibilityXXXL"
                : "UICTContentSizeCategoryL",
        ]
    }

    private func deviceOrientation(for value: String) throws -> UIDeviceOrientation {
        switch value {
        case "portrait": .portrait
        case "landscapeLeft": .landscapeLeft
        case "landscapeRight": .landscapeRight
        default: throw HarnessError.unsupportedOrientation(value)
        }
    }

    @MainActor
    private func waitForDeviceOrientation(
        _ expected: UIDeviceOrientation,
        timeout: TimeInterval = 10
    ) throws {
        let predicate = NSPredicate { _, _ in
            XCUIDevice.shared.orientation == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            XCTFail("Simulator did not reach requested orientation \(expected)")
            throw HarnessError.orientationNotApplied(String(describing: expected))
        }
    }

    private func assertWindowAspect(_ frame: CGRect, matches orientation: String) {
        switch orientation {
        case "portrait":
            XCTAssertGreaterThan(frame.height, frame.width)
        case "landscapeLeft", "landscapeRight":
            XCTAssertGreaterThan(frame.width, frame.height)
        default:
            XCTFail("Unsupported orientation for aspect assertion: \(orientation)")
        }
    }

    @MainActor
    private func waitForWindowAspect(
        _ window: XCUIElement,
        matching orientation: String,
        timeout: TimeInterval = 10
    ) throws {
        let predicate = NSPredicate { _, _ in
            let frame = window.frame
            switch orientation {
            case "portrait": return frame.height > frame.width
            case "landscapeLeft", "landscapeRight": return frame.width > frame.height
            default: return false
            }
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            XCTFail("Application window did not reach \(orientation) aspect")
            throw HarnessError.orientationNotApplied(orientation)
        }
    }

    @MainActor
    private func scroll(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
            app.swipeUp()
        }
        for _ in 0..<12 where !element.isHittable {
            app.swipeDown()
        }
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func removingDirectionalIsolation(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{2066}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

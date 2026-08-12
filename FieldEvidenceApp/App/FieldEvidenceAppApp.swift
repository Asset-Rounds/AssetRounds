import Foundation
import SwiftUI

@main
struct FieldEvidenceAppApp: App {
    private static let invalidPackLaunchArgument = "--s1-invalid-pack"
    private static let lightModeLaunchArgument = "--s1-ui-test-light-mode"
    private static let darkModeLaunchArgument = "--s1-ui-test-dark-mode"

    private let packLoadResult: SignPackLoadResult
    private let preferredColorScheme: ColorScheme?
    private let exposesColorSchemeForUITest: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains(Self.invalidPackLaunchArgument) {
            let malformedPayload = Data(#"{"schemaVersion":1,"unexpected":"content"}"#.utf8)
            packLoadResult = SignPackLoader.load(data: malformedPayload)
        } else {
            packLoadResult = SignPackLoader.loadBundled()
        }

        if arguments.contains(Self.darkModeLaunchArgument) {
            preferredColorScheme = .dark
            exposesColorSchemeForUITest = true
        } else if arguments.contains(Self.lightModeLaunchArgument) {
            preferredColorScheme = .light
            exposesColorSchemeForUITest = true
        } else {
            preferredColorScheme = nil
            exposesColorSchemeForUITest = false
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(
                packLoadResult: packLoadResult,
                exposesColorSchemeForUITest: exposesColorSchemeForUITest
            )
            .preferredColorScheme(preferredColorScheme)
        }
    }
}

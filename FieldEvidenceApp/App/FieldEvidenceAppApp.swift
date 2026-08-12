import Foundation
import SwiftUI

@main
struct FieldEvidenceAppApp: App {
    private static let invalidPackLaunchArgument = "--s1-invalid-pack"

    private let packLoadResult: SignPackLoadResult

    init() {
        if ProcessInfo.processInfo.arguments.contains(Self.invalidPackLaunchArgument) {
            let malformedPayload = Data(#"{"schemaVersion":1,"unexpected":"content"}"#.utf8)
            packLoadResult = SignPackLoader.load(data: malformedPayload)
        } else {
            packLoadResult = SignPackLoader.loadBundled()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(packLoadResult: packLoadResult)
        }
    }
}

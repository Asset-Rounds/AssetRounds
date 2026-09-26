import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Unit-test bundle principal class. Before every test it clears the
/// process-wide private system discovery store, whose durable journal lives in
/// the host app's Application Support directory rather than a test root.
/// Tests reuse deterministic restore/deletion operation IDs; without a reset,
/// entries committed by earlier tests or runs for another workspace collide and
/// the store correctly fails closed.
final class UnitTestIsolationObserverV1: NSObject, XCTestObservation {
    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        #if DEBUG
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        Task.detached {
            do { try await PrivateSystemDiscoveryIndexRuntimeV1.shared.resetDurableStateForTestingV1() }
            catch { failure = error }
            done.signal()
        }
        done.wait()
        if let failure {
            testCase.record(XCTIssue(type: .system,
                compactDescription: "Private discovery isolation reset failed: \(failure)"))
        }
        #endif
    }
}

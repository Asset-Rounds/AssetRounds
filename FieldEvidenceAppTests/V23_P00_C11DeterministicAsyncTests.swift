import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23_P00_C11DeterministicAsyncTests: XCTestCase {
    func testInjectedSleeperRecordsExactDurationWithoutWallClockDelay() async throws {
        let sleeper = RecordingApplicationSleeper()

        try await sleeper.sleep(for: .milliseconds(10))
        let recorded = await sleeper.recordedDurations()

        XCTAssertEqual(recorded, [.milliseconds(10)])
    }

    func testSystemSleeperPreservesCancellation() async {
        let sleeper = SystemApplicationSleeper()
        let operation = Task {
            try await sleeper.sleep(for: .seconds(30))
        }
        operation.cancel()

        do {
            try await operation.value
            XCTFail("A cancelled deterministic delay must throw")
        } catch is CancellationError {
            // Expected cancellation is part of the port contract.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    func testInjectedSleeperRejectsCancellationBeforeRecording() async {
        let sleeper = RecordingApplicationSleeper()
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await sleeper.sleep(for: .milliseconds(10))
        }

        do {
            try await operation.value
            XCTFail("A cancelled injected delay must throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
        let recorded = await sleeper.recordedDurations()
        XCTAssertTrue(recorded.isEmpty)
    }
}

private actor RecordingApplicationSleeper: ApplicationSleeper {
    private var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        durations.append(duration)
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}

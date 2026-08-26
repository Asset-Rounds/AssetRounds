import Foundation

/// A cancellation-preserving delay boundary for deterministic application work.
///
/// Feature and persistence code depend on this port instead of choosing a
/// scheduler or wall-clock implementation directly. Implementations must throw
/// when the enclosing operation is cancelled.
protocol ApplicationSleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

/// Runs CPU-bound, value-only work on a serial executor that is independent of
/// the UI actor. Canonical state must be copied into `Sendable` values before it
/// crosses this boundary; SwiftData models and UI objects never belong here.
///
/// This is the provisional kernel seam consumed by resumable local jobs. The
/// shipping routes remain synchronous until their S10.6 reconciliation binds
/// them to `ResumableLocalJobPortV1`.
actor DeterministicOffMainWorkerV1 {
    func run<Value: Sendable>(
        _ operation: @Sendable () throws -> Value
    ) throws -> Value {
        try Task.checkCancellation()
        let value = try operation()
        try Task.checkCancellation()
        return value
    }
}

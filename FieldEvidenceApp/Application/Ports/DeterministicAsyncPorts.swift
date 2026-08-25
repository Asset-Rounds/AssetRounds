import Foundation

/// A cancellation-preserving delay boundary for deterministic application work.
///
/// Feature and persistence code depend on this port instead of choosing a
/// scheduler or wall-clock implementation directly. Implementations must throw
/// when the enclosing operation is cancelled.
protocol ApplicationSleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

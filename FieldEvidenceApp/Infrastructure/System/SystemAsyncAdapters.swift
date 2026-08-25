import Foundation

struct SystemApplicationSleeper: ApplicationSleeper {
    func sleep(for duration: Duration) async throws {
        try await Task<Never, Never>.sleep(for: duration)
    }
}

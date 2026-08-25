import Foundation

struct SystemApplicationClock: ApplicationClock {
    func now() -> Date {
        Date()
    }
}

struct SystemApplicationIDSource: ApplicationIDSource {
    func makeID() -> UUID {
        UUID()
    }
}

import Foundation

protocol ApplicationClock: Sendable {
    func now() -> Date
}

protocol ApplicationIDSource: Sendable {
    func makeID() -> UUID
}

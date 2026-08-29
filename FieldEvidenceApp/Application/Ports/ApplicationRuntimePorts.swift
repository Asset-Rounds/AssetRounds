import Foundation

protocol ScheduleProjectionClockV1: Sendable { func nowUTC() -> Date }

protocol ApplicationClock: Sendable {
    /// Wall time for durable records and user-visible calendar context only.
    /// It must never be used to order causal mutations or measure durations.
    func now() -> Date
}

/// An in-process monotonic instant. It deliberately has no Codable
/// conformance because monotonic ticks have no meaning after process restart.
struct ApplicationMonotonicInstantV1: Equatable, Comparable, Sendable {
    let uptimeNanoseconds: UInt64

    init(uptimeNanoseconds: UInt64) {
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    static func < (
        lhs: ApplicationMonotonicInstantV1,
        rhs: ApplicationMonotonicInstantV1
    ) -> Bool {
        lhs.uptimeNanoseconds < rhs.uptimeNanoseconds
    }
}

protocol ApplicationMonotonicClockV1: Sendable {
    func instant() -> ApplicationMonotonicInstantV1
}

protocol ApplicationIDSource: Sendable {
    func makeID() -> UUID
}

enum ApplicationFileAuthorityErrorV1: Error, Equatable {
    case invalidComponent
}

/// Produces deterministic, device-local temporary names for a mutation.
///
/// The authority returns a relative path component only. The caller remains
/// responsible for resolving it beneath an already-authorized generation root.
protocol ApplicationFileAuthorityV1: Sendable {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String
}

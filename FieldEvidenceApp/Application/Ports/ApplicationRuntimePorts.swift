import Foundation

protocol ApplicationClock: Sendable {
    func now() -> Date
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

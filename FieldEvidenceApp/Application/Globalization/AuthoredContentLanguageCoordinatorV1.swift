import Foundation

/// Opaque, session-local assessment handle. It holds only candidate provenance,
/// not authored/translated text, and is never serialized or backed up.
struct AuthoredContentTranslationCandidateV1: Equatable, Sendable {
    let provenance: DerivedContentTranslationProvenanceV1
    fileprivate let sessionID: UUID
    fileprivate let generation: UUID
}

@MainActor
final class AuthoredContentLanguageCoordinatorV1 {
    /// All instances of the incumbent canonical writer share this invalidation
    /// boundary. A new coordinator lifetime cannot restore a previous handle.
    static let shared = AuthoredContentLanguageCoordinatorV1()
    private let sessionID = UUID()
    private var generation = UUID()

    func candidate(for provenance: DerivedContentTranslationProvenanceV1,
                   currentSource: AuthoredContentLanguageSourceV1,
                   sourceBytes: Data) throws -> AuthoredContentTranslationCandidateV1 {
        try provenance.validate(); try currentSource.validate(sourceBytes: sourceBytes)
        guard provenance.source == currentSource else {
            throw AuthoredContentLanguageFailureV1.sourceBytesMismatch
        }
        return .init(provenance: provenance, sessionID: sessionID, generation: generation)
    }

    /// The caller must resolve current canonical source/privacy state. A match
    /// proves equality to those supplied bytes, not the authority of the reader.
    /// Reacquiring a handle requires a fresh resolution by that same reader.
    func assess(_ candidate: AuthoredContentTranslationCandidateV1,
                currentSource: AuthoredContentLanguageSourceV1?,
                sourceBytes: Data?) throws -> DerivedContentTranslationAssessmentV1 {
        try candidate.provenance.validate()
        guard candidate.sessionID == sessionID else { return .init(state: .sessionExpired) }
        guard let currentSource, let sourceBytes else { return .init(state: .sourceUnavailable) }
        try currentSource.validate(sourceBytes: sourceBytes)
        let original = candidate.provenance.source
        guard currentSource.workspaceID == original.workspaceID,
              currentSource.sourceID == original.sourceID,
              currentSource.layer == original.layer else { return .init(state: .sourceEdited) }
        // Privacy changes take precedence; unchanged immutable originals do not
        // keep a pre-redaction translation current.
        if currentSource.redactionSHA256 != original.redactionSHA256 {
            return .init(state: .sourceRedacted)
        }
        guard currentSource == original else { return .init(state: .sourceEdited) }
        guard candidate.generation == generation else { return .init(state: .writerInvalidated) }
        return .init(state: .sourceBindingCurrent)
    }

    /// Conservative eviction after successful writer application. The journal
    /// still owns the atomic save; a later rollback may evict a safe candidate
    /// but cannot make stale metadata current. No canonical bytes are changed.
    func invalidateAfterWriterApplication() { generation = UUID() }
}

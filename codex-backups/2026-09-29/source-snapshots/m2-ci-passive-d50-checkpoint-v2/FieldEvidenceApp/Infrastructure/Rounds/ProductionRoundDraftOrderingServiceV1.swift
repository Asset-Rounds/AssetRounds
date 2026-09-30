import Foundation
import SwiftData

enum RoundDraftOrderingAttemptStateV1: Equatable {
    case notAttempted
    case canonicalWriteAttempted
}

/// Private, single-invocation proof retained across an uncertain acknowledgement.
/// It is neither cacheable nor constructible by a presentation caller.
struct RoundDraftOrderingExecutionResultV1 {
    let receipt: RoundSessionMutationReceiptV1
    fileprivate let operationToken: AppAccessGateV1.ContentReadToken
    fileprivate let snapshot: ProductionRoundDraftOrderingServiceV1.LiveContentSnapshot
}

/// A publication-owned command prepared from one exact DRAFT frontier.  It
/// exposes the proposal for UI comparison, never the mutation's writable bytes.
@MainActor
final class PreparedRoundDraftReorderV1 {
    let proposedSession: RoundSessionV1
    let expectedSession: RoundSessionV1
    fileprivate let mutation: RoundSessionMutationV1
    fileprivate let ownerID: UUID
    private(set) var attemptState: RoundDraftOrderingAttemptStateV1 = .notAttempted

    fileprivate init(expectedSession: RoundSessionV1, mutation: RoundSessionMutationV1,
                     ownerID: UUID) {
        self.expectedSession = expectedSession
        self.mutation = mutation
        self.ownerID = ownerID
        proposedSession = mutation.session
    }

    fileprivate func markCanonicalWriteAttempted() {
        attemptState = .canonicalWriteAttempted
    }
}

/// The sole production composition for C07's explicit manual DRAFT ordering.
/// It has no generic writer surface and reconstructs all live readers from the
/// incumbent session immediately around each synchronous operation.
@MainActor
final class ProductionRoundDraftOrderingServiceV1 {
    private weak var session: StoreSessionCoordinator?
    private weak var originalWriter: WorkspaceWriterV1?
    private let workspaceID: WorkspaceID
    private let generationID: UUID
    private let uiGenerationToken: UInt64
    private let generationRootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let accessGate: AppAccessGateV1
    private let content: EvidenceBundleStore
    private let ownerID = UUID()

    #if DEBUG
    var afterContentResolutionForTesting: (@MainActor () async throws -> Void)?
    var afterContentMaterializationForTesting: (@MainActor () async throws -> Void)?
    #endif

    init(session: StoreSessionCoordinator, accessGate: AppAccessGateV1, clock: any ApplicationClock,
         idSource: any ApplicationIDSource) throws {
        self.session = session
        originalWriter = session.workspaceWriter
        workspaceID = session.workspaceID
        generationID = session.generationID
        uiGenerationToken = session.uiGenerationToken
        generationRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        self.clock = clock
        self.idSource = idSource
        self.accessGate = accessGate
        content = EvidenceBundleStore(generationRootURL: session.generationRootURL,
            expectedGenerationRootIdentity: generationRootIdentity)
    }

    func prepare(expected: RoundSessionV1, itemID: UUID, delta: Int,
                 recordedByName: String) throws -> PreparedRoundDraftReorderV1 {
        let current = try currentSession()
        guard expected.workspaceID == workspaceID,
              let currentRound = try makeCoordinator(current).current(sessionID: expected.sessionID),
              currentRound == expected, currentRound.state == .draft,
              delta == -1 || delta == 1,
              let index = currentRound.items.firstIndex(where: { $0.itemID == itemID }) else {
            throw RoundSessionFailureV1.staleRevision
        }
        let destination = index + delta
        guard currentRound.items.indices.contains(destination) else {
            throw RoundSessionFailureV1.illegalTransition
        }
        guard currentRound.revision < UInt64.max else { throw RoundSessionFailureV1.staleRevision }
        guard !recordedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RoundSessionFailureV1.authorityMismatch
        }

        var items = currentRound.items
        items.swapAt(index, destination)
        items = try items.enumerated().map { offset, item in
            try RoundItemV1(itemID: item.itemID, order: offset, selection: item.selection,
                             requirement: item.requirement, disposition: item.disposition,
                             visit: item.visit, reason: item.reason, completion: item.completion)
        }
        let actorID = idSource.makeID()
        let snapshotID = idSource.makeID()
        guard actorID != snapshotID else { throw RoundSessionFailureV1.authorityMismatch }
        let sampled = clock.now().timeIntervalSince1970
        guard sampled.isFinite else { throw RoundSessionFailureV1.authorityMismatch }
        let now = Date(timeIntervalSince1970: floor(sampled * 1_000) / 1_000)
        let actor = try LocalActorReferenceV1(actorReferenceID: actorID, workspaceID: workspaceID,
                                              displayName: recordedByName)
        let recordedBy = try ActorSnapshotV1(snapshotID: snapshotID, workspaceID: workspaceID,
            actor: actor, responsibility: .recordedBy, displayNameAtTime: recordedByName,
            capturedAt: now)
        let mutationID = try MutationIDV1(rawValue: idSource.makeID())
        let successor = try RoundSessionV1(workspaceID: workspaceID, sessionID: currentRound.sessionID,
            predecessor: currentRound, revision: currentRound.revision + 1, mutationID: mutationID,
            state: .draft, transition: .reviseSelection, items: items, recordedBy: recordedBy,
            recordedAt: now)
        let mutation = try RoundSessionMutationV1(workspaceID: workspaceID,
            expectedRevision: currentRound.revision, mutationID: mutationID, session: successor)
        try sourceClosure(current).validatePrepared(expected: currentRound, proposal: successor)
        return PreparedRoundDraftReorderV1(expectedSession: currentRound, mutation: mutation,
                                            ownerID: ownerID)
    }

    func execute(_ prepared: PreparedRoundDraftReorderV1,
                 authorizing access: AppAccessPresentationV1.ContentAccess,
                 validateIntent: @MainActor () throws -> Void) async throws -> RoundDraftOrderingExecutionResultV1 {
        guard prepared.ownerID == ownerID else { throw RoundSessionFailureV1.authorityMismatch }
        try access.withRead {}
        let token = try await accessGate.beginContentRead(for: .render)
        let current = try currentSession()
        let sources = try sourceClosure(current)
        try sources.validatePrepared(expected: prepared.expectedSession, proposal: prepared.proposedSession)
        let revision = try current.workspaceWriter.currentRevision()
        let sourceSHA = try sources.sha256()
        @MainActor func validatePreparedFrontier() throws {
            let live = try currentSession()
            let liveSources = try sourceClosure(live)
            guard live === current, try live.workspaceWriter.currentRevision() == revision,
                  try liveSources.sha256() == sourceSHA else {
                throw RoundSessionFailureV1.staleRevision
            }
            try liveSources.validatePrepared(expected: prepared.expectedSession,
                                             proposal: prepared.proposedSession)
        }
        let references = try contentReferences(expected: prepared.expectedSession, proposal: prepared.proposedSession)
        var resolved: [ContentKey: ContentOutcome] = [:]
        for reference in references {
            try Task.checkCancellation()
            let value = try await content.resolveContentReference(reference)
            #if DEBUG
            try await afterContentResolutionForTesting?()
            #endif
            try Task.checkCancellation()
            try await accessGate.validateContentRead(token, for: .render)
            try access.withRead {}
            try validatePreparedFrontier()
            let key = ContentKey(reference)
            if let value {
                guard value == reference else { throw RoundSessionFailureV1.authorityMismatch }
                resolved[key] = .present(value)
            } else { resolved[key] = .absent }
        }
        #if DEBUG
        try await afterContentMaterializationForTesting?()
        #endif
        try await accessGate.validateContentRead(token, for: .render)
        try access.withRead {}
        try validatePreparedFrontier()
        try await accessGate.validateContentRead(token, for: .render)
        try validateIntent()
        let prewriteSnapshot = LiveContentSnapshot(ownerID: ownerID, expected: try prepared.expectedSession.reference,
            proposed: try prepared.proposedSession.reference, revision: revision, sourceSHA: sourceSHA,
            root: generationRootIdentity, values: resolved)
        return try access.withRead {
            let final = try currentSession()
            guard try final.workspaceWriter.currentRevision() == prewriteSnapshot.revision,
                  try sourceClosure(final).sha256() == prewriteSnapshot.sourceSHA,
                  try ReportPDFAnchoredFile.rootIdentity(at: final.generationRootURL) == prewriteSnapshot.root else {
                throw RoundSessionFailureV1.staleRevision
            }
            let coordinator = try makeCoordinator(final, sources: try sourceClosure(final), snapshot: prewriteSnapshot)
            let receipt = try coordinator.save(prepared.mutation) {
                try validatePreparedFrontier()
                prepared.markCanonicalWriteAttempted()
            }
            guard receipt.sessionFrontier == (try prepared.proposedSession.reference) else { throw RoundSessionFailureV1.authorityMismatch }
            let post = try currentSession()
            let postSnapshot = LiveContentSnapshot(ownerID: ownerID,
                expected: prewriteSnapshot.expected, proposed: prewriteSnapshot.proposed,
                revision: try post.workspaceWriter.currentRevision(), sourceSHA: try sourceClosure(post).sha256(),
                root: try ReportPDFAnchoredFile.rootIdentity(at: post.generationRootURL), values: prewriteSnapshot.values)
            return RoundDraftOrderingExecutionResultV1(receipt: receipt,
                operationToken: token, snapshot: postSnapshot)
        }
    }

    /// Uses only the exact materialized invocation proof, never a synthetic
    /// absence, cached snapshot, second content read, or newly minted token.
    func validateForPublication(_ result: RoundDraftOrderingExecutionResultV1,
                                authorizing access: AppAccessPresentationV1.ContentAccess) throws {
        guard result.snapshot.ownerID == ownerID else { throw RoundSessionFailureV1.authorityMismatch }
        try result.operationToken.withContentRead(for: .render) {}
        try access.withRead {
            let current = try currentSession()
            let snapshot = result.snapshot
            guard try current.workspaceWriter.currentRevision() == snapshot.revision,
                  try sourceClosure(current).sha256() == snapshot.sourceSHA,
                  try ReportPDFAnchoredFile.rootIdentity(at: current.generationRootURL) == snapshot.root else {
                throw RoundSessionFailureV1.staleRevision
            }
            let coordinator = try makeCoordinator(current, sources: try sourceClosure(current), snapshot: snapshot)
            let value = try coordinator.validateCurrentFrontier(snapshot.proposed)
            guard try value.reference == snapshot.proposed else { throw RoundSessionFailureV1.staleRevision }
        }
    }

    private func currentSession() throws -> StoreSessionCoordinator {
        guard let session, let originalWriter, originalWriter === session.workspaceWriter,
              session.workspaceID == workspaceID, session.generationID == generationID,
              session.uiGenerationToken == uiGenerationToken, !session.modelContext.hasChanges,
              try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL) == generationRootIdentity else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        return session
    }

    private func sourceClosure(_ session: StoreSessionCoordinator) throws
        -> ProductionOfflineReadinessSourceClosureV1 {
        try ProductionOfflineReadinessSourceClosureV1(context: session.modelContext,
                                                      workspaceID: workspaceID)
    }

    private func makeCoordinator(_ session: StoreSessionCoordinator,
        sources: ProductionOfflineReadinessSourceClosureV1? = nil, snapshot: LiveContentSnapshot? = nil) throws -> RoundSessionCoordinatorV1 {
        let adapter = WorkspaceWriterAdapterV1(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            expectedRootIdentity: try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL),
            lifecycleProfileRegistry: session.lifecycleProfileRegistry)
        let resolvedSources: ProductionOfflineReadinessSourceClosureV1
        if let sources { resolvedSources = sources }
        else { resolvedSources = try sourceClosure(session) }
        return RoundSessionCoordinatorV1(workspaceID: workspaceID, reader: adapter,
            writer: session.workspaceWriter,
            authority: LiveAuthority(session: session, sources: resolvedSources, snapshot: snapshot))
    }

    fileprivate struct ContentKey: Hashable {
        let workspaceID: String; let contentID: String
        init(_ value: ContentReferenceV1) { workspaceID = value.workspaceID; contentID = value.contentID }
        init(workspaceID: String, contentID: String) { self.workspaceID = workspaceID; self.contentID = contentID }
    }
    fileprivate enum ContentOutcome { case absent; case present(ContentReferenceV1) }
    fileprivate struct LiveContentSnapshot {
        let ownerID: UUID; let expected: RoundSessionReferenceV1; let proposed: RoundSessionReferenceV1
        let revision: WorkspaceRevisionV1; let sourceSHA: String; let root: ReportPDFAnchoredFile.RootIdentity
        let values: [ContentKey: ContentOutcome]
        func value(workspaceID: WorkspaceID, contentID: String) throws -> ContentReferenceV1? {
            guard let outcome = values[.init(workspaceID: workspaceID.rawValue.uuidString.lowercased(), contentID: contentID)] else { throw RoundSessionFailureV1.authorityMismatch }
            switch outcome { case .absent: return nil; case let .present(value): return value }
        }
    }
    private func contentReferences(expected: RoundSessionV1, proposal: RoundSessionV1) throws -> [ContentReferenceV1] {
        guard expected.items.count == proposal.items.count,
              expected.items.allSatisfy({ old in
                  proposal.items.contains { $0.itemID == old.itemID && $0.requirement == old.requirement }
              }) else { throw RoundSessionFailureV1.authorityMismatch }
        var values: [ContentKey: ContentReferenceV1] = [:]
        for reference in expected.items.flatMap(\.requirement.requiredContent) {
            guard reference.workspaceID == workspaceID.rawValue.uuidString.lowercased() else { throw RoundSessionFailureV1.authorityMismatch }
            let key = ContentKey(reference)
            if let old = values[key], old != reference { throw RoundSessionFailureV1.authorityMismatch }
            values[key] = reference
        }
        return values.values.sorted { ($0.workspaceID, $0.contentID) < ($1.workspaceID, $1.contentID) }
    }
    private final class LiveAuthority: RoundSessionLiveAuthorityReadingV1 {
        unowned let session: StoreSessionCoordinator
        let sources: ProductionOfflineReadinessSourceClosureV1
        let snapshot: LiveContentSnapshot?
        init(session: StoreSessionCoordinator, sources: ProductionOfflineReadinessSourceClosureV1, snapshot: LiveContentSnapshot?) {
            self.session = session; self.sources = sources; self.snapshot = snapshot
        }
        func publishedPackageRelease(for reference: RoundPackageReleaseReferenceV1) throws -> InspectionPackageReleaseV1? {
            try sources.package(for: reference)
        }
        func contentReference(workspaceID: WorkspaceID, contentID: String) throws -> ContentReferenceV1? {
            guard workspaceID == session.workspaceID else { throw RoundSessionFailureV1.authorityMismatch }
            guard let snapshot else { throw RoundSessionFailureV1.authorityMismatch }
            return try snapshot.value(workspaceID: workspaceID, contentID: contentID)
        }
        func assetExists(workspaceID: WorkspaceID, assetID: UUID) throws -> Bool {
            guard workspaceID == session.workspaceID else { throw RoundSessionFailureV1.authorityMismatch }
            return sources.assets.contains { $0.id == assetID }
        }
        func completionMatches(workspaceID: WorkspaceID, reference: RoundItemCompletionReferenceV1,
                               assetID: UUID, packageRelease: RoundPackageReleaseReferenceV1) throws -> Bool {
            false
        }
    }
}

private extension ProductionOfflineReadinessSourceClosureV1 {
    func validatePrepared(expected: RoundSessionV1, proposal: RoundSessionV1) throws {
        guard expected.workspaceID == proposal.workspaceID, expected.sessionID == proposal.sessionID,
              expected.state == .draft, proposal.state == .draft,
              proposal.transition == .reviseSelection,
              expected.items.count == proposal.items.count else {
            throw RoundSessionFailureV1.staleRevision
        }
        let changed = zip(expected.items, proposal.items).enumerated().filter { $0.element.0 != $0.element.1 }
        guard changed.count == 2, changed[1].offset == changed[0].offset + 1 else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        let left = changed[0].element, right = changed[1].element
        guard left.0.itemID == right.1.itemID, right.0.itemID == left.1.itemID,
              left.0.selection == right.1.selection, right.0.selection == left.1.selection,
              left.0.requirement == right.1.requirement, right.0.requirement == left.1.requirement,
              left.0.disposition == right.1.disposition, right.0.disposition == left.1.disposition,
              left.0.visit == right.1.visit, right.0.visit == left.1.visit,
              left.0.reason == right.1.reason, right.0.reason == left.1.reason,
              left.0.completion == right.1.completion, right.0.completion == left.1.completion else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        _ = try RoundSessionHistoryValidatorV1.validate(
            rounds.filter { $0.sessionID == expected.sessionID },
            workspaceID: expected.workspaceID, sessionID: expected.sessionID
        )
    }
}

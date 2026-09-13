import Foundation
import SwiftData

enum RoundSessionTransitionAttemptStateV1: Equatable { case notAttempted, canonicalWriteAttempted }

struct RoundSessionTransitionExecutionResultV1 {
    let receipt: RoundSessionMutationReceiptV1
    fileprivate let operationToken: AppAccessGateV1.ContentReadToken
    fileprivate let snapshot: ProductionRoundSessionTransitionServiceV1.LiveContentSnapshot
}

@MainActor
final class PreparedRoundSessionTransitionV1 {
    let proposedSession: RoundSessionV1
    let expectedSession: RoundSessionV1
    fileprivate let mutation: RoundSessionMutationV1
    fileprivate let ownerID: UUID
    private(set) var attemptState: RoundSessionTransitionAttemptStateV1 = .notAttempted
    fileprivate init(expectedSession: RoundSessionV1, mutation: RoundSessionMutationV1, ownerID: UUID) {
        self.expectedSession = expectedSession; self.mutation = mutation; self.ownerID = ownerID
        proposedSession = mutation.session
    }
    fileprivate func markCanonicalWriteAttempted() { attemptState = .canonicalWriteAttempted }
}

/// Publication-owned C07 session and C05 item transitions. This has no generic
/// writer surface and retains one immutable materialized content proof through
/// an uncertain acknowledgement.
@MainActor
final class ProductionRoundSessionTransitionServiceV1 {
    private weak var session: StoreSessionCoordinator?
    private weak var originalWriter: WorkspaceWriterV1?
    private let workspaceID: WorkspaceID; private let generationID: UUID; private let uiGenerationToken: UInt64
    private let generationRootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let clock: any ApplicationClock; private let idSource: any ApplicationIDSource
    private let accessGate: AppAccessGateV1; private let content: EvidenceBundleStore; private let ownerID = UUID()
    #if DEBUG
    var afterContentResolutionForTesting: (@MainActor () async throws -> Void)?
    var afterContentMaterializationForTesting: (@MainActor () async throws -> Void)?
    #endif

    init(session: StoreSessionCoordinator, accessGate: AppAccessGateV1, clock: any ApplicationClock,
         idSource: any ApplicationIDSource) throws {
        self.session = session; originalWriter = session.workspaceWriter; workspaceID = session.workspaceID
        generationID = session.generationID; uiGenerationToken = session.uiGenerationToken
        generationRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        self.clock = clock; self.idSource = idSource; self.accessGate = accessGate
        content = EvidenceBundleStore(generationRootURL: session.generationRootURL,
            expectedGenerationRootIdentity: generationRootIdentity)
    }

    func prepare(expected: RoundSessionV1, transition: RoundSessionTransitionV1,
                 recordedByName: String) throws -> PreparedRoundSessionTransitionV1 {
        guard [.start, .pause, .resume].contains(transition),
              !recordedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        let current = try currentSession()
        guard expected.workspaceID == workspaceID, let frontier = try makeCoordinator(current).current(sessionID: expected.sessionID),
              frontier == expected, frontier.revision < UInt64.max else { throw RoundSessionFailureV1.staleRevision }
        let state: RoundSessionStateV1
        switch transition { case .start: guard frontier.state == .draft else { throw RoundSessionFailureV1.illegalTransition }; state = .active
        case .pause: guard frontier.state == .active else { throw RoundSessionFailureV1.illegalTransition }; state = .paused
        case .resume: guard frontier.state == .paused else { throw RoundSessionFailureV1.illegalTransition }; state = .active
        default: throw RoundSessionFailureV1.illegalTransition }
        let actorID = idSource.makeID(), snapshotID = idSource.makeID(), mutationRawID = idSource.makeID()
        guard Set([actorID, snapshotID, mutationRawID]).count == 3 else { throw RoundSessionFailureV1.authorityMismatch }
        let sampled = clock.now().timeIntervalSince1970
        guard sampled.isFinite else { throw RoundSessionFailureV1.authorityMismatch }
        let now = Date(timeIntervalSince1970: floor(sampled * 1_000) / 1_000)
        let actor = try LocalActorReferenceV1(actorReferenceID: actorID, workspaceID: workspaceID, displayName: recordedByName)
        let recorded = try ActorSnapshotV1(snapshotID: snapshotID, workspaceID: workspaceID, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: recordedByName, capturedAt: now)
        let mutationID = try MutationIDV1(rawValue: mutationRawID)
        let successor = try RoundSessionV1(workspaceID: workspaceID, sessionID: frontier.sessionID,
            predecessor: frontier, revision: frontier.revision + 1, mutationID: mutationID, state: state,
            transition: transition, items: frontier.items, recordedBy: recorded, recordedAt: now)
        let mutation = try RoundSessionMutationV1(workspaceID: workspaceID, expectedRevision: frontier.revision,
            mutationID: mutationID, session: successor)
        try Self.validateTransition(expected: frontier, proposal: successor)
        return .init(expectedSession: frontier, mutation: mutation, ownerID: ownerID)
    }

    func prepareItem(expected: RoundSessionV1, itemID: UUID,
                     transition: RoundSessionTransitionV1, reason: RoundItemReasonV1? = nil,
                     completion: RoundItemCompletionReferenceV1? = nil,
                     recordedByName: String) throws -> PreparedRoundSessionTransitionV1 {
        guard Self.itemTransitions.contains(transition),
              !recordedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        let current = try currentSession()
        guard expected.workspaceID == workspaceID,
              let frontier = try makeCoordinator(current).current(sessionID: expected.sessionID),
              frontier == expected, frontier.revision < UInt64.max else {
            throw RoundSessionFailureV1.staleRevision
        }
        guard frontier.state == .active,
              let index = frontier.items.firstIndex(where: { $0.itemID == itemID }) else {
            throw RoundSessionFailureV1.illegalTransition
        }
        let old = frontier.items[index]
        let disposition: RoundItemDispositionV1
        switch transition {
        case .visitItem:
            guard reason == nil, completion == nil else { throw RoundSessionFailureV1.itemMismatch }
            disposition = .visited
        case .completeItem:
            guard reason == nil, completion != nil else { throw RoundSessionFailureV1.itemMismatch }
            disposition = .completed
        case .markInaccessible, .skipItem, .deferItem:
            guard reason != nil, completion == nil else { throw RoundSessionFailureV1.itemMismatch }
            switch transition {
            case .markInaccessible: disposition = .inaccessible
            case .skipItem: disposition = .skipped
            default: disposition = .deferred
            }
        case .retryItem:
            guard reason == nil, completion == nil else { throw RoundSessionFailureV1.itemMismatch }
            disposition = old.visit == nil ? .pending : .visited
        default:
            throw RoundSessionFailureV1.illegalTransition
        }
        let actorID = idSource.makeID(), snapshotID = idSource.makeID(), mutationRawID = idSource.makeID()
        guard Set([actorID, snapshotID, mutationRawID]).count == 3 else { throw RoundSessionFailureV1.authorityMismatch }
        let sampled = clock.now().timeIntervalSince1970
        guard sampled.isFinite else { throw RoundSessionFailureV1.authorityMismatch }
        let now = Date(timeIntervalSince1970: floor(sampled * 1_000) / 1_000)
        let actor = try LocalActorReferenceV1(actorReferenceID: actorID, workspaceID: workspaceID, displayName: recordedByName)
        let recorded = try ActorSnapshotV1(snapshotID: snapshotID, workspaceID: workspaceID, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: recordedByName, capturedAt: now)
        let mutationID = try MutationIDV1(rawValue: mutationRawID)
        let visit: RoundItemVisitV1?
        if transition == .visitItem {
            visit = try RoundItemVisitV1(visitedAt: now, recordedBy: recorded)
        } else {
            visit = old.visit
        }
        var items = frontier.items
        items[index] = try RoundItemV1(itemID: old.itemID, order: old.order, selection: old.selection,
            requirement: old.requirement, disposition: disposition, visit: visit, reason: reason,
            completion: completion)
        let successor = try RoundSessionV1(workspaceID: workspaceID, sessionID: frontier.sessionID,
            predecessor: frontier, revision: frontier.revision + 1, mutationID: mutationID, state: .active,
            transition: transition, transitionItemID: itemID, items: items, recordedBy: recorded, recordedAt: now)
        let mutation = try RoundSessionMutationV1(workspaceID: workspaceID, expectedRevision: frontier.revision,
            mutationID: mutationID, session: successor)
        try Self.validateTransition(expected: frontier, proposal: successor)
        return .init(expectedSession: frontier, mutation: mutation, ownerID: ownerID)
    }

    /// Readout is limited to an item mutation prepared by this exact owner.
    /// C36 persists these bytes before the existing execute path can run.
    func validateRepetitiveCaptureOwner(_ expected: StoreSessionCoordinator) throws {
        guard try currentSession() === expected else { throw RoundSessionFailureV1.authorityMismatch }
    }

    func repetitiveCaptureMutation(for prepared: PreparedRoundSessionTransitionV1) throws -> RoundSessionMutationV1 {
        _ = try currentSession()
        guard prepared.ownerID == ownerID,
              [.visitItem, .completeItem, .deferItem].contains(prepared.proposedSession.transition),
              prepared.proposedSession.transitionItemID != nil else { throw RoundSessionFailureV1.authorityMismatch }
        try Self.validateTransition(expected: prepared.expectedSession, proposal: prepared.proposedSession)
        return prepared.mutation
    }

    /// Cold recovery accepts only the unique authenticated pending C36 tip.
    /// It never prepares a new mutation or samples a new identity or timestamp.
    func adoptPendingRepetitiveCaptureStep(sourceDraftID: UUID, stepDraftID: UUID) throws
        -> PreparedRoundSessionTransitionV1 {
        let current = try currentSession()
        let drafts = try current.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: current.modelContext)
        let chain = try drafts.reviewedRepetitiveCaptureProgress(workspaceID: workspaceID,
                                                                 sourceDraftID: sourceDraftID)
        guard let tip = chain.nodes.last, tip.checkpoint.draftID == stepDraftID,
              tip.isPendingRoundEffect, let mutation = tip.step.roundMutation,
              [.enter, .complete, .defer].contains(tip.step.action),
              chain.currentRound == tip.step.expectedRound,
              [.visitItem, .completeItem, .deferItem].contains(mutation.session.transition) else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        try Self.validateTransition(expected: tip.step.expectedRound, proposal: mutation.session)
        try sourceClosure(current).validatePrepared(expected: tip.step.expectedRound, proposal: mutation.session)
        return .init(expectedSession: tip.step.expectedRound, mutation: mutation, ownerID: ownerID)
    }

    func execute(_ prepared: PreparedRoundSessionTransitionV1, authorizing access: AppAccessPresentationV1.ContentAccess,
                 validateIntent: @MainActor () throws -> Void) async throws -> RoundSessionTransitionExecutionResultV1 {
        try Task.checkCancellation()
        guard prepared.ownerID == ownerID else { throw RoundSessionFailureV1.authorityMismatch }
        try access.withRead {}; let token = try await accessGate.beginContentRead(for: .render)
        let current = try currentSession(), sources = try sourceClosure(current)
        try sources.validatePrepared(expected: prepared.expectedSession, proposal: prepared.proposedSession)
        let revision = try current.workspaceWriter.currentRevision(), sourceSHA = try sources.sha256()
        @MainActor func fence() throws {
            let live = try currentSession(), liveSources = try sourceClosure(live)
            guard live === current, try live.workspaceWriter.currentRevision() == revision, try liveSources.sha256() == sourceSHA else { throw RoundSessionFailureV1.staleRevision }
            try liveSources.validatePrepared(expected: prepared.expectedSession, proposal: prepared.proposedSession)
        }
        let references = try contentReferences(expected: prepared.expectedSession, proposal: prepared.proposedSession)
        var values: [ContentKey: ContentOutcome] = [:]
        for reference in references {
            try Task.checkCancellation(); let resolved = try await content.resolveContentReference(reference)
            #if DEBUG
            try await afterContentResolutionForTesting?()
            #endif
            try Task.checkCancellation(); try await accessGate.validateContentRead(token, for: .render); try access.withRead {}; try fence()
            let key = ContentKey(reference)
            if let resolved { guard resolved == reference else { throw RoundSessionFailureV1.authorityMismatch }; values[key] = .present(resolved) }
            else { values[key] = .absent }
        }
        #if DEBUG
        try await afterContentMaterializationForTesting?()
        #endif
        try await accessGate.validateContentRead(token, for: .render); try access.withRead {}; try fence(); try Task.checkCancellation(); try validateIntent()
        let snapshot = LiveContentSnapshot(ownerID: ownerID, expected: try prepared.expectedSession.reference,
            proposed: try prepared.proposedSession.reference, revision: revision, sourceSHA: sourceSHA,
            root: generationRootIdentity, round: prepared.proposedSession, values: values)
        return try access.withRead {
            let final = try currentSession()
            guard try final.workspaceWriter.currentRevision() == snapshot.revision,
                  try sourceClosure(final).sha256() == snapshot.sourceSHA,
                  try ReportPDFAnchoredFile.rootIdentity(at: final.generationRootURL) == snapshot.root else { throw RoundSessionFailureV1.staleRevision }
            let receipt = try makeCoordinator(final, sources: try sourceClosure(final), snapshot: snapshot).save(prepared.mutation) {
                try Task.checkCancellation(); try fence(); prepared.markCanonicalWriteAttempted()
            }
            guard receipt.sessionFrontier == (try prepared.proposedSession.reference) else { throw RoundSessionFailureV1.authorityMismatch }
            let post = try currentSession()
            return .init(receipt: receipt, operationToken: token, snapshot: .init(ownerID: ownerID,
                expected: snapshot.expected, proposed: snapshot.proposed, revision: try post.workspaceWriter.currentRevision(),
                sourceSHA: try sourceClosure(post).sha256(), root: try ReportPDFAnchoredFile.rootIdentity(at: post.generationRootURL),
                round: prepared.proposedSession, values: values))
        }
    }

    func validateForPublication(_ result: RoundSessionTransitionExecutionResultV1,
                                authorizing access: AppAccessPresentationV1.ContentAccess) throws {
        guard result.snapshot.ownerID == ownerID else { throw RoundSessionFailureV1.authorityMismatch }
        try result.operationToken.withContentRead(for: .render) {}
        try access.withRead {
            let current = try currentSession(), snapshot = result.snapshot
            guard try current.workspaceWriter.currentRevision() == snapshot.revision, try sourceClosure(current).sha256() == snapshot.sourceSHA,
                  try ReportPDFAnchoredFile.rootIdentity(at: current.generationRootURL) == snapshot.root else { throw RoundSessionFailureV1.staleRevision }
            let value = try makeCoordinator(current, sources: try sourceClosure(current), snapshot: snapshot).validateCurrentFrontier(snapshot.proposed)
            guard try value.reference == snapshot.proposed else { throw RoundSessionFailureV1.staleRevision }
        }
    }

    private func currentSession() throws -> StoreSessionCoordinator {
        guard let session, let originalWriter, originalWriter === session.workspaceWriter, session.workspaceID == workspaceID,
              session.generationID == generationID, session.uiGenerationToken == uiGenerationToken, !session.modelContext.hasChanges,
              try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL) == generationRootIdentity else { throw RoundSessionFailureV1.authorityMismatch }
        return session
    }
    private func sourceClosure(_ session: StoreSessionCoordinator) throws -> ProductionOfflineReadinessSourceClosureV1 { try .init(context: session.modelContext, workspaceID: workspaceID) }
    private func makeCoordinator(_ session: StoreSessionCoordinator, sources: ProductionOfflineReadinessSourceClosureV1? = nil,
                                 snapshot: LiveContentSnapshot? = nil) throws -> RoundSessionCoordinatorV1 {
        let adapter = WorkspaceWriterAdapterV1(modelContext: session.modelContext, generationRootURL: session.generationRootURL,
            expectedRootIdentity: try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL), lifecycleProfileRegistry: session.lifecycleProfileRegistry)
        let resolvedSources: ProductionOfflineReadinessSourceClosureV1
        if let sources { resolvedSources = sources }
        else { resolvedSources = try sourceClosure(session) }
        return .init(workspaceID: workspaceID, reader: adapter, writer: session.workspaceWriter,
            authority: LiveAuthority(session: session, sources: resolvedSources, snapshot: snapshot))
    }
    fileprivate struct ContentKey: Hashable { let workspaceID: String; let contentID: String; init(_ value: ContentReferenceV1) { workspaceID = value.workspaceID; contentID = value.contentID }; init(workspaceID: String, contentID: String) { self.workspaceID = workspaceID; self.contentID = contentID } }
    fileprivate enum ContentOutcome { case absent; case present(ContentReferenceV1) }
    fileprivate struct LiveContentSnapshot { let ownerID: UUID; let expected: RoundSessionReferenceV1; let proposed: RoundSessionReferenceV1; let revision: WorkspaceRevisionV1; let sourceSHA: String; let root: ReportPDFAnchoredFile.RootIdentity; let round: RoundSessionV1; let values: [ContentKey: ContentOutcome]
        func value(workspaceID: WorkspaceID, contentID: String) throws -> ContentReferenceV1? { guard let value = values[.init(workspaceID: workspaceID.rawValue.uuidString.lowercased(), contentID: contentID)] else { throw RoundSessionFailureV1.authorityMismatch }; switch value { case .absent: return nil; case let .present(value): return value } } }
    private func contentReferences(expected: RoundSessionV1, proposal: RoundSessionV1) throws -> [ContentReferenceV1] {
        try Self.validateTransition(expected: expected, proposal: proposal); var values: [ContentKey: ContentReferenceV1] = [:]
        for reference in expected.items.flatMap(\.requirement.requiredContent) { guard reference.workspaceID == workspaceID.rawValue.uuidString.lowercased() else { throw RoundSessionFailureV1.authorityMismatch }; let key = ContentKey(reference); if let old = values[key], old != reference { throw RoundSessionFailureV1.authorityMismatch }; values[key] = reference }
        return values.values.sorted { ($0.workspaceID, $0.contentID) < ($1.workspaceID, $1.contentID) }
    }
    nonisolated private static let itemTransitions: [RoundSessionTransitionV1] = [
        .visitItem, .completeItem, .markInaccessible, .skipItem, .deferItem, .retryItem
    ]
    nonisolated fileprivate static func validateTransition(expected: RoundSessionV1, proposal: RoundSessionV1) throws {
        guard expected.workspaceID == proposal.workspaceID, expected.sessionID == proposal.sessionID else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        if itemTransitions.contains(proposal.transition) {
            guard expected.state == .active, proposal.state == .active,
                  proposal.transitionItemID != nil else { throw RoundSessionFailureV1.authorityMismatch }
        } else {
            guard proposal.items == expected.items, proposal.transitionItemID == nil,
                  [.start, .pause, .resume].contains(proposal.transition) else {
                throw RoundSessionFailureV1.authorityMismatch
            }
        }
        try proposal.validateSuccessor(of: expected)
    }
    private final class LiveAuthority: RoundSessionLiveAuthorityReadingV1 {
        unowned let session: StoreSessionCoordinator; let sources: ProductionOfflineReadinessSourceClosureV1; let snapshot: LiveContentSnapshot?
        init(session: StoreSessionCoordinator, sources: ProductionOfflineReadinessSourceClosureV1, snapshot: LiveContentSnapshot?) { self.session = session; self.sources = sources; self.snapshot = snapshot }
        func publishedPackageRelease(for reference: RoundPackageReleaseReferenceV1) throws -> InspectionPackageReleaseV1? { try sources.package(for: reference) }
        func contentReference(workspaceID: WorkspaceID, contentID: String) throws -> ContentReferenceV1? { guard workspaceID == session.workspaceID, let snapshot else { throw RoundSessionFailureV1.authorityMismatch }; return try snapshot.value(workspaceID: workspaceID, contentID: contentID) }
        func assetExists(workspaceID: WorkspaceID, assetID: UUID) throws -> Bool { guard workspaceID == session.workspaceID else { throw RoundSessionFailureV1.authorityMismatch }; return sources.assets.contains { $0.id == assetID } }
        func completionMatches(workspaceID: WorkspaceID, reference: RoundItemCompletionReferenceV1, assetID: UUID, packageRelease: RoundPackageReleaseReferenceV1) throws -> Bool {
            guard workspaceID == session.workspaceID, let snapshot,
                  snapshot.round.items.contains(where: { item in
                      item.completion == reference && item.selection.assetID == assetID &&
                          item.requirement.packageRelease == packageRelease
                  }) else { return false }
            return try ProductionOfflineReadinessAuthorityV1.completedItemsMatch(
                snapshot.round, sources: sources, session: session)
        }
    }
}

private extension ProductionOfflineReadinessSourceClosureV1 {
    func validatePrepared(expected: RoundSessionV1, proposal: RoundSessionV1) throws {
        try ProductionRoundSessionTransitionServiceV1.validateTransition(expected: expected, proposal: proposal)
        let current = try RoundSessionHistoryValidatorV1.validate(
            rounds.filter { $0.sessionID == expected.sessionID },
            workspaceID: expected.workspaceID, sessionID: expected.sessionID)
        guard current == expected || current == proposal else {
            throw RoundSessionFailureV1.staleRevision
        }
    }
}

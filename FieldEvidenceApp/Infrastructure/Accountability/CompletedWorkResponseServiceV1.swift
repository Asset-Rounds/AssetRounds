import Foundation
import SwiftData

enum CompletedWorkResponseFailureV1: Error, Equatable, Sendable {
    case stale
    case unavailable
    case invalidSubmission
    case notFound
}

enum CompletedWorkResponseAttemptStateV1: Equatable, Sendable {
    case notAttempted
    case canonicalWriteAttempted
}

/// One prepared approval response. It is owned by the service that prepared
/// it; any other service instance refuses it. The actor and signoff plans are
/// kept after their first preview so that a retry after an uncertain
/// acknowledgement is receipt-first and never writes twice.
@MainActor
final class PreparedCompletedWorkResponseV1 {
    let key: CompletedWorkSubjectKeyV1
    let proof: CompletedWorkSubjectProofV1
    let typedName: String
    let claimedRole: String
    let claimedRelationship: SitePartyRoleV1?
    let drawnMark: SignoffEnrollmentDrawnMarkV1?
    fileprivate let ownerID: UUID
    fileprivate let actor: ActorSnapshotV1
    fileprivate let signoffMutationID: MutationIDV1
    fileprivate let occurredAt: Date
    fileprivate let recordedAt: Date
    fileprivate var actorPlan: PartyAccountabilityChangePlanV1?
    fileprivate var signoffPlan: SignoffEnrollmentPlanV1?
    private(set) var receipt: SignoffEnrollmentReceiptV1?
    private(set) var attemptState: CompletedWorkResponseAttemptStateV1 = .notAttempted

    /// The acknowledged-by actor snapshot this operation appends. Exposed for
    /// read-only verification; it carries no Party join.
    var actorSnapshotID: UUID { actor.snapshotID }

    fileprivate init(
        key: CompletedWorkSubjectKeyV1,
        proof: CompletedWorkSubjectProofV1,
        typedName: String,
        claimedRole: String,
        claimedRelationship: SitePartyRoleV1?,
        drawnMark: SignoffEnrollmentDrawnMarkV1?,
        ownerID: UUID,
        actor: ActorSnapshotV1,
        signoffMutationID: MutationIDV1,
        occurredAt: Date,
        recordedAt: Date
    ) {
        self.key = key
        self.proof = proof
        self.typedName = typedName
        self.claimedRole = claimedRole
        self.claimedRelationship = claimedRelationship
        self.drawnMark = drawnMark
        self.ownerID = ownerID
        self.actor = actor
        self.signoffMutationID = signoffMutationID
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
    }

    fileprivate func markCanonicalWriteAttempted() {
        attemptState = .canonicalWriteAttempted
    }

    fileprivate func complete(with receipt: SignoffEnrollmentReceiptV1) {
        self.receipt = receipt
    }
}

// MARK: - History values

/// Stored response facts only. There is no identifier, no Party join and no
/// verification claim.
struct CompletedWorkResponseFactsV1: Hashable, Sendable {
    let typedName: String
    let claimedRole: String
    let claimedRelationship: SitePartyRoleV1?
    let method: SignoffMethodV1
    let occurredAt: Date
    let recordedAt: Date
    let disclosureText: String

    var methodText: String {
        switch method {
        case .typedLocalAssertion:
            return "Typed response"
        case .explicitLocalAcknowledgement:
            return "Typed response with drawn mark — mark not stored"
        case .externalEvidenceReference, .noAssertion:
            return "Unsupported method"
        }
    }

    var relationshipText: String? {
        guard let claimedRelationship else { return nil }
        return claimedRelationship.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .capitalized
    }
}

/// One history row. `facts` is nil for an unsupported response record. The
/// `id` is used only for list identity and is never displayed.
struct CompletedWorkResponseHistoryEntryV1: Hashable, Identifiable, Sendable {
    let id: UUID
    let isFocused: Bool
    let version: UInt64?
    let facts: CompletedWorkResponseFactsV1?
}

/// Responses grouped for the history screen. `subject` is the frozen display
/// of the focused response's completed work; when nil and
/// `unavailableReason` is set, the screen shows "Completed work unavailable".
struct CompletedWorkResponseHistoryV1: Hashable, Sendable {
    let subject: CompletedWorkSubjectDisplayV1?
    let unavailableReason: CompletedWorkSubjectUnavailableReasonV1?
    let current: [CompletedWorkResponseHistoryEntryV1]
    let earlier: [CompletedWorkResponseHistoryEntryV1]
}

/// Read-only history projection over stored `SignoffSnapshotV1` rows.
@MainActor
struct CompletedWorkResponseHistoryReaderV1 {
    private static let maximumRows = 100_000
    let resolver: CompletedWorkSubjectResolverV1

    init(resolver: CompletedWorkSubjectResolverV1) {
        self.resolver = resolver
    }

    nonisolated private static var purpose: String {
        SignoffEnrollmentManifestV1.workDetailCompletedResponseV1.purpose
    }

    private func decodedSignoffs() throws -> (values: [SignoffSnapshotV1], rows: [SignoffSnapshotRow]) {
        guard !resolver.modelContext.hasChanges else {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        var descriptor = FetchDescriptor<SignoffSnapshotRow>()
        descriptor.fetchLimit = Self.maximumRows + 1
        let rows = try resolver.modelContext.fetch(descriptor)
        guard rows.count <= Self.maximumRows else {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        var values: [SignoffSnapshotV1] = []
        for row in rows {
            if let value = try? row.value() {
                values.append(value)
            }
        }
        return (values, rows)
    }

    nonisolated private static func supportsBoundary(_ value: SignoffSnapshotV1) -> Bool {
        (try? C43SignoffEnrollmentBoundaryV1.validate(value)) != nil
    }

    nonisolated private static func facts(_ value: SignoffSnapshotV1) -> CompletedWorkResponseFactsV1? {
        guard let assertion = value.roleAssertion else { return nil }
        return CompletedWorkResponseFactsV1(
            typedName: assertion.actor.displayNameAtTime,
            claimedRole: assertion.claimedRole,
            claimedRelationship: assertion.claimedRelationship,
            method: value.method,
            occurredAt: value.occurredAt ?? value.recordedAt,
            recordedAt: value.recordedAt,
            disclosureText: assertion.disclosureRelease.disclosureText
        )
    }

    nonisolated private static func newestFirst(_ lhs: SignoffSnapshotV1, _ rhs: SignoffSnapshotV1) -> Bool {
        if lhs.recordedAt != rhs.recordedAt {
            return lhs.recordedAt > rhs.recordedAt
        }
        return lhs.snapshotID.uuidString.lowercased() < rhs.snapshotID.uuidString.lowercased()
    }

    /// Supported C43 responses bound to each exact completed-work version.
    func boundResponseCounts() throws -> [CompletedWorkSubjectKeyV1: Int] {
        let values = try decodedSignoffs().values
        var counts: [CompletedWorkSubjectKeyV1: Int] = [:]
        for value in values where value.workspaceID == resolver.workspaceID
            && value.purpose == Self.purpose
            && Self.supportsBoundary(value) {
            guard let key = try? CompletedWorkSubjectKeyV1(signoff: value) else { continue }
            counts[key, default: 0] += 1
        }
        return counts
    }

    func history(focusedSignoffID: UUID) throws -> CompletedWorkResponseHistoryV1 {
        let decoded = try decodedSignoffs()
        let focusedRows = decoded.rows.filter { $0.snapshotID == focusedSignoffID }
        guard focusedRows.count == 1 else { throw CompletedWorkResponseFailureV1.notFound }
        let unsupportedFocused = CompletedWorkResponseHistoryV1(
            subject: nil,
            unavailableReason: nil,
            current: [CompletedWorkResponseHistoryEntryV1(
                id: focusedSignoffID, isFocused: true, version: nil, facts: nil
            )],
            earlier: []
        )
        guard let focused = decoded.values.first(where: { $0.snapshotID == focusedSignoffID }),
              focused.workspaceID == resolver.workspaceID,
              focused.purpose == Self.purpose,
              let focusedKey = try? CompletedWorkSubjectKeyV1(signoff: focused) else {
            return unsupportedFocused
        }

        let chain = try resolver.chain(containing: focused.subjectID)
        if let chain, chain.positions[focused.subjectID] != focused.subjectRevision {
            // A C43 record whose position disagrees with its subject's chain
            // position is an unsupported response record.
            return unsupportedFocused
        }
        let memberIDs: Set<UUID>
        if let chain {
            memberIDs = Set(chain.positions.keys)
        } else {
            memberIDs = [focused.subjectID]
        }
        let candidates = decoded.values
            .filter {
                $0.workspaceID == resolver.workspaceID
                    && $0.purpose == Self.purpose
                    && memberIDs.contains($0.subjectID)
            }
            .sorted(by: Self.newestFirst)

        var current: [CompletedWorkResponseHistoryEntryV1] = []
        var earlier: [CompletedWorkResponseHistoryEntryV1] = []
        for value in candidates {
            let expectedPosition: UInt64? = chain?.positions[value.subjectID]
            let positionMatches = expectedPosition.map { $0 == value.subjectRevision } ?? true
            let facts: CompletedWorkResponseFactsV1?
            if Self.supportsBoundary(value), positionMatches {
                facts = Self.facts(value)
            } else {
                facts = nil
            }
            let entry = CompletedWorkResponseHistoryEntryV1(
                id: value.snapshotID,
                isFocused: value.snapshotID == focusedSignoffID,
                version: facts == nil ? expectedPosition : Optional(value.subjectRevision),
                facts: facts
            )
            let isCurrent: Bool
            if let chain {
                isCurrent = chain.tipReportID == value.subjectID
            } else {
                isCurrent = true
            }
            if isCurrent {
                current.append(entry)
            } else {
                earlier.append(entry)
            }
        }

        switch resolver.resolve(focusedKey) {
        case let .resolved(proof):
            return CompletedWorkResponseHistoryV1(
                subject: proof.display,
                unavailableReason: nil,
                current: current,
                earlier: earlier
            )
        case let .unavailable(reason):
            // Response facts remain visible; the subject is never substituted.
            return CompletedWorkResponseHistoryV1(
                subject: nil,
                unavailableReason: reason,
                current: current,
                earlier: earlier
            )
        }
    }
}

// MARK: - Service

/// SIG-1 application service: prepare, record, retry and history for C43
/// approval responses on completed work. It reuses the existing
/// `PartyAccountabilityCoordinatorV1` and `SignoffEnrollmentCoordinatorV1`
/// through the one existing `WorkspaceWriterV1`; it never opens another writer,
/// saves the context directly or changes a workflow record.
@MainActor
final class CompletedWorkResponseServiceV1 {
    private let modelContext: ModelContext
    private let writer: WorkspaceWriterV1
    private let workspaceID: WorkspaceID
    private let generationID: UUID
    private let generationRootURL: URL
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let signPack: SignPack
    private let ownerID = UUID()

    #if DEBUG
    /// Test-only interruption after the actor append returned. It cannot
    /// supply identity, subject or writer state; a throw models a lost
    /// acknowledgement or a crash between the two canonical writes.
    var afterActorAppendForTesting: (@MainActor () throws -> Void)?
    /// Test-only interruption after the signoff commit returned. A throw
    /// models a lost acknowledgement after the durable save.
    var afterSignoffCommitForTesting: (@MainActor () throws -> Void)?
    #endif

    init(
        modelContext: ModelContext,
        writer: WorkspaceWriterV1,
        workspaceID: WorkspaceID,
        generationID: UUID,
        generationRootURL: URL,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        signPack: SignPack
    ) {
        self.modelContext = modelContext
        self.writer = writer
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.clock = clock
        self.idSource = idSource
        self.signPack = signPack
    }

    private func makeResolver() -> CompletedWorkSubjectResolverV1 {
        CompletedWorkSubjectResolverV1(
            modelContext: modelContext,
            workspaceID: workspaceID,
            generationID: generationID,
            generationRootURL: generationRootURL,
            signPack: signPack
        )
    }

    /// Same writer generation and a context with no unsaved changes.
    private func requireFence() throws {
        guard !modelContext.hasChanges else {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        let revision: WorkspaceRevisionV1
        do {
            revision = try writer.currentRevision()
        } catch {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        guard revision.workspaceID == workspaceID,
              revision.generationID == generationID else {
            throw CompletedWorkResponseFailureV1.unavailable
        }
    }

    private func currentExpectedRevision() throws -> WorkspaceExpectedRevisionV1 {
        WorkspaceExpectedRevisionV1(snapshot: try writer.currentRevision())
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    // MARK: Read cache

    /// Canonical state identity for cached reads: the writer revision and
    /// generation, plus the journal's mutable-semantic checkpoint, which also
    /// moves for authorized external mutations such as whole-sign deletion.
    private struct ReadCacheKeyV1: Equatable {
        let workspaceID: WorkspaceID
        let generationID: UUID
        let writerInstanceID: UUID
        let workspaceRevision: UInt64
        let mutableSemanticSHA256: String?
    }

    /// Lightweight cached projections only: listings and counts, never
    /// snapshot or media bytes.
    private struct CachedReadsV1 {
        let key: ReadCacheKeyV1
        var counts: [CompletedWorkSubjectKeyV1: Int]
        var listings: [CompletedWorkSubjectListingV1]?
    }

    private var cachedReads: CachedReadsV1?

    /// The fence plus the current cache identity. A changed identity simply
    /// misses the cache, which invalidates it.
    private func currentReadCacheKey() throws -> ReadCacheKeyV1 {
        guard !modelContext.hasChanges else {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        let revision: WorkspaceRevisionV1
        let states: [WorkspaceMutationStateRow]
        do {
            revision = try writer.currentRevision()
            let workspace = workspaceID.rawValue
            var descriptor = FetchDescriptor<WorkspaceMutationStateRow>(
                predicate: #Predicate { $0.workspaceID == workspace }
            )
            descriptor.fetchLimit = 2
            states = try modelContext.fetch(descriptor)
        } catch {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        guard revision.workspaceID == workspaceID,
              revision.generationID == generationID,
              states.count == 1, let state = states.first,
              state.generationID == generationID else {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        return ReadCacheKeyV1(
            workspaceID: workspaceID,
            generationID: generationID,
            writerInstanceID: revision.writerInstanceID,
            workspaceRevision: revision.revision,
            mutableSemanticSHA256: state.mutableSemanticSHA256
        )
    }

    private func boundResponseCounts(
        for cacheKey: ReadCacheKeyV1,
        resolver: CompletedWorkSubjectResolverV1
    ) throws -> [CompletedWorkSubjectKeyV1: Int] {
        if let cached = cachedReads, cached.key == cacheKey {
            return cached.counts
        }
        let counts = try CompletedWorkResponseHistoryReaderV1(resolver: resolver)
            .boundResponseCounts()
        cachedReads = CachedReadsV1(key: cacheKey, counts: counts, listings: nil)
        return counts
    }

    // MARK: Reads

    /// Current-tip completed work for the Work root, newest first, capped.
    /// Cached until the canonical state identity changes; every record still
    /// validates its subject twice before writing.
    func completedWork() throws -> [CompletedWorkSubjectListingV1] {
        let cacheKey = try currentReadCacheKey()
        if let cached = cachedReads, cached.key == cacheKey, let listings = cached.listings {
            return listings
        }
        let resolver = makeResolver()
        let counts = try boundResponseCounts(for: cacheKey, resolver: resolver)
        let tips = try resolver.currentTips()
        var listings: [CompletedWorkSubjectListingV1] = []
        for tip in tips {
            let count = counts[tip.key] ?? 0
            switch tip.resolution {
            case let .resolved(proof):
                listings.append(CompletedWorkSubjectListingV1(
                    key: tip.key, display: proof.display,
                    eligibility: proof.eligibility, responseCount: count
                ))
            case let .unavailable(reason):
                listings.append(CompletedWorkSubjectListingV1(
                    key: tip.key, display: nil,
                    eligibility: .unavailable(reason), responseCount: count
                ))
            }
        }
        cachedReads = CachedReadsV1(key: cacheKey, counts: counts, listings: listings)
        return listings
    }

    /// One subject, fully validated on demand; only the lightweight proof is
    /// returned. Response counts come from the same cached projection.
    func subjectDetail(_ key: CompletedWorkSubjectKeyV1) throws -> CompletedWorkSubjectDetailV1 {
        let cacheKey = try currentReadCacheKey()
        let resolver = makeResolver()
        let counts = try boundResponseCounts(for: cacheKey, resolver: resolver)
        switch resolver.resolve(key) {
        case let .resolved(proof):
            return CompletedWorkSubjectDetailV1(
                key: key, proof: proof, eligibility: proof.eligibility,
                responseCount: counts[key] ?? 0
            )
        case let .unavailable(reason):
            return CompletedWorkSubjectDetailV1(
                key: key, proof: nil, eligibility: .unavailable(reason),
                responseCount: counts[key] ?? 0
            )
        }
    }

    func history(focusedSignoffID: UUID) throws -> CompletedWorkResponseHistoryV1 {
        try requireFence()
        return try CompletedWorkResponseHistoryReaderV1(resolver: makeResolver())
            .history(focusedSignoffID: focusedSignoffID)
    }

    // MARK: Prepare

    /// Prepares one response against the proof the editor opened with. A
    /// changed or superseded subject is `.stale`; nothing is written here.
    func prepare(
        submission: SignoffEnrollmentSubmissionV1,
        expectedProof: CompletedWorkSubjectProofV1
    ) throws -> PreparedCompletedWorkResponseV1 {
        try requireFence()
        let route = submission.route
        guard route.workspaceID == workspaceID,
              expectedProof.workspaceID == workspaceID,
              expectedProof.generationID == generationID,
              route.subjectID == expectedProof.reportID,
              route.subjectRevision == expectedProof.chainPosition,
              route.purpose == SignoffEnrollmentManifestV1.workDetailCompletedResponseV1.purpose else {
            throw CompletedWorkResponseFailureV1.invalidSubmission
        }
        let key: CompletedWorkSubjectKeyV1
        do {
            key = try expectedProof.key
        } catch {
            throw CompletedWorkResponseFailureV1.invalidSubmission
        }
        switch makeResolver().resolve(key) {
        case .unavailable:
            throw CompletedWorkResponseFailureV1.unavailable
        case let .resolved(current):
            guard current == expectedProof, current.isTip else {
                throw CompletedWorkResponseFailureV1.stale
            }
        }

        let typedName = Self.normalized(submission.typedName)
        let claimedRole = Self.normalized(submission.claimedRole)
        let actorReferenceID = idSource.makeID()
        let actorSnapshotID = idSource.makeID()
        guard actorReferenceID != actorSnapshotID else {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        let sampled = clock.now().timeIntervalSince1970
        guard sampled.isFinite else { throw CompletedWorkResponseFailureV1.unavailable }
        let now = Date(timeIntervalSince1970: floor(sampled * 1_000) / 1_000)

        let actor: ActorSnapshotV1
        let signoffMutationID: MutationIDV1
        do {
            let reference = try LocalActorReferenceV1(
                actorReferenceID: actorReferenceID,
                workspaceID: workspaceID,
                displayName: typedName
            )
            actor = try ActorSnapshotV1(
                snapshotID: actorSnapshotID,
                workspaceID: workspaceID,
                actor: reference,
                responsibility: .acknowledgedBy,
                displayNameAtTime: typedName,
                capturedAt: now
            )
            signoffMutationID = try writer.makeMutationID()
            // Validates the complete C43 request shape before any write.
            _ = try SignoffEnrollmentRequestV1(
                workspaceID: workspaceID,
                subjectID: key.subjectID,
                subjectRevision: key.subjectRevision,
                expectedRevision: try currentExpectedRevision(),
                actorSnapshot: actor,
                typedName: typedName,
                claimedRole: claimedRole,
                claimedRelationship: submission.claimedRelationship,
                occurredAt: now,
                recordedAt: now,
                drawnMark: submission.drawnMark,
                mutationID: signoffMutationID
            )
        } catch {
            throw CompletedWorkResponseFailureV1.invalidSubmission
        }
        return PreparedCompletedWorkResponseV1(
            key: key,
            proof: expectedProof,
            typedName: typedName,
            claimedRole: claimedRole,
            claimedRelationship: submission.claimedRelationship,
            drawnMark: submission.drawnMark,
            ownerID: ownerID,
            actor: actor,
            signoffMutationID: signoffMutationID,
            occurredAt: now,
            recordedAt: now
        )
    }

    // MARK: Record

    /// One synchronous main-actor call: check subject, append the
    /// acknowledged-by actor (receipt-first), check subject again, preview and
    /// keep the signoff plan, commit it (receipt-first), and read the row back.
    /// Calling it again with the same prepared operation is the Try again path.
    func record(_ prepared: PreparedCompletedWorkResponseV1) -> CompletedWorkResponseOutcomeV1 {
        guard prepared.ownerID == ownerID else { return .unavailable }
        if let receipt = prepared.receipt { return .saved(receipt) }
        // Try again after a lost signoff acknowledgement: a durable receipt
        // for the kept plan is the answer, whatever happened to the subject
        // since. It is acknowledged receipt-first and never written twice.
        if let kept = prepared.signoffPlan,
           let recovered = recoverDurableSignoff(kept, prepared: prepared) {
            return recovered
        }

        // 1. Check the subject.
        if let blocked = checkSubject(prepared) { return blocked }

        // 2. Append the actor snapshot, receipt-first, with the writer's own
        //    mutation identity minted at its first preview.
        let party = PartyAccountabilityCoordinatorV1(writer: writer, idSource: idSource)
        let actorPlan: PartyAccountabilityChangePlanV1
        if let kept = prepared.actorPlan {
            actorPlan = kept
        } else {
            do {
                actorPlan = try party.preview(
                    mutation: .appendActorSnapshot(prepared.actor),
                    expectedRevision: try currentExpectedRevision(),
                    workspaceID: workspaceID
                )
            } catch {
                return .unavailable
            }
            prepared.actorPlan = actorPlan
        }
        prepared.markCanonicalWriteAttempted()
        do {
            _ = try party.commit(actorPlan)
            #if DEBUG
            try afterActorAppendForTesting?()
            #endif
        } catch {
            return unresolvedCommit(
                mutationID: actorPlan.mutationID,
                prepared: prepared,
                discard: { $0.actorPlan = nil }
            )
        }

        // 3. Check the subject again, immediately before the signoff.
        if let blocked = checkSubject(prepared) { return blocked }

        // 4. Preview at the writer's current revision with the fixed signoff
        //    mutation identity, keeping the plan.
        let enrollment = SignoffEnrollmentCoordinatorV1(
            partyCoordinator: party,
            idSource: idSource
        )
        let signoffPlan: SignoffEnrollmentPlanV1
        if let kept = prepared.signoffPlan {
            signoffPlan = kept
        } else {
            do {
                let request = try SignoffEnrollmentRequestV1(
                    workspaceID: workspaceID,
                    subjectID: prepared.key.subjectID,
                    subjectRevision: prepared.key.subjectRevision,
                    expectedRevision: try currentExpectedRevision(),
                    actorSnapshot: prepared.actor,
                    typedName: prepared.typedName,
                    claimedRole: prepared.claimedRole,
                    claimedRelationship: prepared.claimedRelationship,
                    occurredAt: prepared.occurredAt,
                    recordedAt: prepared.recordedAt,
                    drawnMark: prepared.drawnMark,
                    mutationID: prepared.signoffMutationID
                )
                signoffPlan = try enrollment.preview(request)
            } catch {
                return .unavailable
            }
            prepared.signoffPlan = signoffPlan
        }

        // 5. Commit through commitC43SignoffEnrollment, receipt-first.
        let receipt: SignoffEnrollmentReceiptV1
        do {
            receipt = try enrollment.commit(signoffPlan)
            #if DEBUG
            try afterSignoffCommitForTesting?()
            #endif
        } catch {
            return unresolvedCommit(
                mutationID: signoffPlan.partyPlan.mutationID,
                prepared: prepared,
                discard: { $0.signoffPlan = nil }
            )
        }

        // 6. Read the durable row back.
        guard readBack(receipt: receipt, plan: signoffPlan, prepared: prepared) else {
            return .uncertain
        }
        prepared.complete(with: receipt)
        return .saved(receipt)
    }

    /// Returns nil when the kept signoff plan has no durable receipt, so the
    /// ordinary checked path continues. Any doubt stays `.uncertain`.
    private func recoverDurableSignoff(
        _ plan: SignoffEnrollmentPlanV1,
        prepared: PreparedCompletedWorkResponseV1
    ) -> CompletedWorkResponseOutcomeV1? {
        let durable: MutationReceiptV1?
        do {
            try requireFence()
            durable = try writer.durableReceipt(mutationID: plan.partyPlan.mutationID)
        } catch {
            return .uncertain
        }
        guard durable != nil else { return nil }
        let party = PartyAccountabilityCoordinatorV1(writer: writer, idSource: idSource)
        let enrollment = SignoffEnrollmentCoordinatorV1(partyCoordinator: party, idSource: idSource)
        do {
            let receipt = try enrollment.commit(plan)
            guard readBack(receipt: receipt, plan: plan, prepared: prepared) else {
                return .uncertain
            }
            prepared.complete(with: receipt)
            return .saved(receipt)
        } catch {
            return .uncertain
        }
    }

    private func checkSubject(
        _ prepared: PreparedCompletedWorkResponseV1
    ) -> CompletedWorkResponseOutcomeV1? {
        do {
            try requireFence()
        } catch {
            return .unavailable
        }
        switch makeResolver().resolve(prepared.key) {
        case .unavailable:
            return .unavailable
        case let .resolved(proof):
            guard proof == prepared.proof, proof.isTip else { return .stale }
            return nil
        }
    }

    /// A commit threw. A durable receipt means the write happened and its
    /// acknowledgement was lost: keep the plan and report `.uncertain`. With
    /// no receipt the write did not happen: discard the plan and recheck.
    private func unresolvedCommit(
        mutationID: MutationIDV1,
        prepared: PreparedCompletedWorkResponseV1,
        discard: @MainActor (PreparedCompletedWorkResponseV1) -> Void
    ) -> CompletedWorkResponseOutcomeV1 {
        let durable: MutationReceiptV1?
        do {
            durable = try writer.durableReceipt(mutationID: mutationID)
        } catch {
            return .uncertain
        }
        if durable != nil { return .uncertain }
        discard(prepared)
        if let blocked = checkSubject(prepared) { return blocked }
        // The subject is still current: the response was not recorded and
        // the same prepared operation can be tried again.
        return .notRecorded
    }

    private func readBack(
        receipt: SignoffEnrollmentReceiptV1,
        plan: SignoffEnrollmentPlanV1,
        prepared: PreparedCompletedWorkResponseV1
    ) -> Bool {
        guard case let .appendSignoff(planned) = plan.partyPlan.basis.mutation,
              receipt.snapshotID == planned.snapshotID else {
            return false
        }
        let snapshotID = receipt.snapshotID
        let descriptor = FetchDescriptor<SignoffSnapshotRow>(
            predicate: #Predicate { $0.snapshotID == snapshotID }
        )
        guard let rows = try? modelContext.fetch(descriptor), rows.count == 1,
              let stored = try? rows[0].value() else {
            return false
        }
        return stored == planned
            && stored.workspaceID == workspaceID
            && stored.subjectID == prepared.key.subjectID
            && stored.subjectRevision == prepared.key.subjectRevision
            && stored.roleAssertion?.actor == prepared.actor
            && stored.supersedesSnapshotID == nil
    }
}

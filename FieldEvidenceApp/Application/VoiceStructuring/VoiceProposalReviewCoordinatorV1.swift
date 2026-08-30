import CryptoKit
import Foundation

enum VoiceProposalReviewCoordinatorFailureV1: Error, Equatable, Sendable {
    case proposalNotFound
    case divergentProposalReplay
    case divergentFieldReplay
    case reviewInProgress
    case incompleteReview
    case cleanupInProgress
    case activeProposalLimitExceeded
    case terminalizedProposal
    case staleGeneration
}

enum VoiceProposalTerminalDispositionV1: String, Equatable, Sendable {
    case completed
    case cancelled
    case expired
    case generationRevoked
    case erasedOrReset
}

/// Review values are admitted against the exact released grammar that created
/// this proposal. Generic value-kind validation is intentionally insufficient
/// for closed enum fields because it cannot distinguish a value from another
/// field's vocabulary.
private enum VoiceProposalReviewValidationV1 {
    static func validate(
        review: VoiceProposalFieldReviewV1,
        field: StructuredVoiceFieldProposalV1,
        proposal: StructuredVoiceProposalV1,
        grammar: VoiceStructuringGrammarReleaseV1
    ) throws {
        try proposal.validate(grammar: grammar)
        guard proposal.fields.first(where: { $0.fieldID == field.fieldID }) == field,
              review.fieldID == field.fieldID else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        switch review.disposition {
        case .accept:
            guard field.resolution == .exact,
                  review.reviewedValue == field.proposedValue,
                  let value = review.reviewedValue else {
                throw VoiceStructuringFailureV1.invalidValue
            }
            try validateEnumMembership(value: value, field: field, grammar: grammar)
        case .edit:
            guard let value = review.reviewedValue else {
                throw VoiceStructuringFailureV1.invalidValue
            }
            try value.validate(for: field.kind)
            try validateEnumMembership(value: value, field: field, grammar: grammar)
        case .reject:
            guard review.reviewedValue == nil else {
                throw VoiceStructuringFailureV1.invalidValue
            }
        }
    }

    private static func validateEnumMembership(
        value: VoiceStructuredFieldValueV1,
        field: StructuredVoiceFieldProposalV1,
        grammar: VoiceStructuringGrammarReleaseV1
    ) throws {
        guard field.kind == .allowedEnum else { return }
        guard case let .allowedEnum(rawValue) = value else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        try grammar.validateAllowedEnumValue(rawValue, for: field.fieldID)
    }
}

/// C36's exact checkpoint frontier. It is supplied by one trusted atomic
/// snapshot and becomes the compare-and-swap precondition for one field.
struct VoiceProposalDraftCheckpointFrontierV1: Equatable, Sendable {
    let checkpoint: FieldDraftCheckpointV1
    let workspaceID: WorkspaceID
    let draftID: UUID
    let scope: DraftScopeKeyV1
    let draftRevision: UInt64
    let baseCanonicalRevision: UInt64
    let checkpointSHA256: String

    init(checkpoint: FieldDraftCheckpointV1) throws {
        try checkpoint.validate()
        self.checkpoint = checkpoint
        workspaceID = checkpoint.workspaceID
        draftID = checkpoint.draftID
        scope = checkpoint.scope
        draftRevision = checkpoint.draftRevision
        baseCanonicalRevision = checkpoint.baseCanonicalRevision
        checkpointSHA256 = checkpoint.checkpointSHA256
    }
}

/// The only C36 update C56 may request. It contains no transcript, source
/// spans, audio bytes, writer, or generic canonical command. The mutation ID
/// and digest are deterministic per proposal/field/review/frontier, allowing
/// the C36 adapter to return an identical persisted effect or no effect.
struct VoiceProposalDraftCheckpointUpdateV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let draftID: UUID
    let scope: DraftScopeKeyV1
    let expectedDraftRevision: UInt64
    let expectedBaseCanonicalRevision: UInt64
    let expectedCheckpointSHA256: String
    let predecessor: FieldDraftCheckpointV1
    let mutationID: MutationIDV1
    let proposalID: UUID
    let proposalSHA256: String
    let grammarReleaseSHA256: String
    let fieldID: String
    let fieldKind: VoiceStructuredFieldKindV1
    let disposition: VoiceProposalFieldReviewDispositionV1
    let value: VoiceStructuredFieldValueV1
    let reviewedAt: Date
    let updateSHA256: String

    init(
        proposal: StructuredVoiceProposalV1,
        field: StructuredVoiceFieldProposalV1,
        review: VoiceProposalFieldReviewV1,
        snapshot: VoiceProposalTrustedSnapshotV1
    ) throws {
        try snapshot.validate(for: proposal)
        try field.validate()
        guard review.fieldID == field.fieldID,
              review.disposition == .accept || review.disposition == .edit,
              let reviewedValue = review.reviewedValue else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        try VoiceProposalReviewValidationV1.validate(
            review: review,
            field: field,
            proposal: proposal,
            grammar: snapshot.grammar
        )
        try reviewedValue.validate(for: field.kind)
        let proposalDigest = try proposal.proposalSHA256
        let frontier = snapshot.draftFrontier
        let mutationSeed = try VoiceStructuringCanonicalCodecV1.sha256(MutationSeed(
            workspaceID: frontier.workspaceID,
            proposalID: proposal.proposalID,
            proposalSHA256: proposalDigest,
            generationID: snapshot.generationID,
            draftID: frontier.draftID,
            scope: frontier.scope,
            expectedDraftRevision: frontier.draftRevision,
            expectedBaseCanonicalRevision: frontier.baseCanonicalRevision,
            expectedCheckpointSHA256: frontier.checkpointSHA256,
            grammarReleaseSHA256: proposal.grammarReleaseSHA256,
            fieldID: field.fieldID,
            fieldKind: field.kind,
            disposition: review.disposition,
            value: reviewedValue,
            reviewedAt: snapshot.observedAt
        ))
        let mutationID = try Self.mutationID(seed: mutationSeed)
        let workspace = frontier.workspaceID
        let generation = snapshot.generationID
        let draft = frontier.draftID
        let draftScope = frontier.scope
        let expectedDraft = frontier.draftRevision
        let expectedBase = frontier.baseCanonicalRevision
        let expectedCheckpoint = frontier.checkpointSHA256
        let reviewInstant = snapshot.observedAt
        let digest = try VoiceStructuringCanonicalCodecV1.sha256(Basis(
            workspaceID: workspace,
            generationID: generation,
            draftID: draft,
            scope: draftScope,
            expectedDraftRevision: expectedDraft,
            expectedBaseCanonicalRevision: expectedBase,
            expectedCheckpointSHA256: expectedCheckpoint,
            mutationID: mutationID,
            proposalID: proposal.proposalID,
            proposalSHA256: proposalDigest,
            grammarReleaseSHA256: proposal.grammarReleaseSHA256,
            fieldID: field.fieldID,
            fieldKind: field.kind,
            disposition: review.disposition,
            value: reviewedValue,
            reviewedAt: reviewInstant
        ))
        workspaceID = workspace
        generationID = generation
        draftID = draft
        scope = draftScope
        expectedDraftRevision = expectedDraft
        expectedBaseCanonicalRevision = expectedBase
        expectedCheckpointSHA256 = expectedCheckpoint
        predecessor = frontier.checkpoint
        self.mutationID = mutationID
        proposalID = proposal.proposalID
        proposalSHA256 = proposalDigest
        grammarReleaseSHA256 = proposal.grammarReleaseSHA256
        fieldID = field.fieldID
        fieldKind = field.kind
        disposition = review.disposition
        value = reviewedValue
        reviewedAt = reviewInstant
        updateSHA256 = digest
    }

    private static func mutationID(seed: String) throws -> MutationIDV1 {
        let digest = Array(SHA256.hash(data: Data(seed.utf8)))
        let value = UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        ))
        return try MutationIDV1(rawValue: value)
    }

    private struct MutationSeed: Codable {
        let workspaceID: WorkspaceID
        let proposalID: UUID
        let proposalSHA256: String
        let generationID: UUID
        let draftID: UUID
        let scope: DraftScopeKeyV1
        let expectedDraftRevision: UInt64
        let expectedBaseCanonicalRevision: UInt64
        let expectedCheckpointSHA256: String
        let grammarReleaseSHA256: String
        let fieldID: String
        let fieldKind: VoiceStructuredFieldKindV1
        let disposition: VoiceProposalFieldReviewDispositionV1
        let value: VoiceStructuredFieldValueV1
        let reviewedAt: Date
    }

    private struct Basis: Codable {
        let workspaceID: WorkspaceID
        let generationID: UUID
        let draftID: UUID
        let scope: DraftScopeKeyV1
        let expectedDraftRevision: UInt64
        let expectedBaseCanonicalRevision: UInt64
        let expectedCheckpointSHA256: String
        let mutationID: MutationIDV1
        let proposalID: UUID
        let proposalSHA256: String
        let grammarReleaseSHA256: String
        let fieldID: String
        let fieldKind: VoiceStructuredFieldKindV1
        let disposition: VoiceProposalFieldReviewDispositionV1
        let value: VoiceStructuredFieldValueV1
        let reviewedAt: Date
    }
}

/// Adapter-produced evidence that the typed C36 payload was updated for this
/// one reviewed field. The coordinator binds it to both the requested value
/// and the read-back checkpoint payload digest; it never decodes C36's opaque
/// draft codec itself.
struct VoiceProposalDraftCheckpointApplicationV1: Equatable, Sendable {
    let fieldID: String
    let fieldKind: VoiceStructuredFieldKindV1
    let value: VoiceStructuredFieldValueV1
    let successorPayloadSHA256: String

    init(
        fieldID: String,
        fieldKind: VoiceStructuredFieldKindV1,
        value: VoiceStructuredFieldValueV1,
        successorPayloadSHA256: String
    ) throws {
        try VoiceStructuringLimitsV1.identifier(fieldID)
        try value.validate(for: fieldKind)
        try VoiceStructuringLimitsV1.digest(successorPayloadSHA256)
        self.fieldID = fieldID
        self.fieldKind = fieldKind
        self.value = value
        self.successorPayloadSHA256 = successorPayloadSHA256
    }
}

/// C36 returns both the durable receipt and the read-back successor. The
/// coordinator accepts neither a receipt-only claim nor an unverified draft
/// checkpoint successor.
struct VoiceProposalDraftCheckpointResultV1: Equatable, Sendable {
    let updateSHA256: String
    let mutation: FieldDraftMutationV1
    let mutationReceipt: MutationReceiptV1
    let successor: FieldDraftCheckpointV1
    let application: VoiceProposalDraftCheckpointApplicationV1

    init(
        update: VoiceProposalDraftCheckpointUpdateV1,
        mutation: FieldDraftMutationV1,
        mutationReceipt: MutationReceiptV1,
        successor: FieldDraftCheckpointV1,
        application: VoiceProposalDraftCheckpointApplicationV1
    ) throws {
        _ = try FieldDraftMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: mutationReceipt
        )
        try successor.validateSuccessor(
            of: update.predecessor,
            expectedDraftRevision: update.expectedDraftRevision,
            expectedBaseRevision: update.expectedBaseCanonicalRevision
        )
        let (nextRevision, overflow) = update.expectedDraftRevision.addingReportingOverflow(1)
        guard !overflow,
              update.predecessor.checkpointSHA256 == update.expectedCheckpointSHA256,
              mutation.workspaceID == update.workspaceID,
              mutation.expectedRevision == update.expectedDraftRevision,
              mutation.expectedBaseCanonicalRevision == update.expectedBaseCanonicalRevision,
              mutation.mutationID == update.mutationID,
              mutation.postImage == .reviseCheckpoint(successor),
              mutationReceipt.mutationID == update.mutationID,
              successor.workspaceID == update.workspaceID,
              successor.draftID == update.draftID,
              successor.scope == update.scope,
              successor.baseCanonicalRevision == update.expectedBaseCanonicalRevision,
              successor.draftRevision == nextRevision,
              successor.mutationID == update.mutationID,
              application.fieldID == update.fieldID,
              application.fieldKind == update.fieldKind,
              application.value == update.value,
              application.successorPayloadSHA256 == successor.payloadSHA256 else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        updateSHA256 = update.updateSHA256
        self.mutation = mutation
        self.mutationReceipt = mutationReceipt
        self.successor = successor
        self.application = application
    }

    func frontier() throws -> VoiceProposalDraftCheckpointFrontierV1 {
        try VoiceProposalDraftCheckpointFrontierV1(checkpoint: successor)
    }
}

/// Narrow C36 ownership boundary. The adapter must first return a validated
/// existing result for identical retry, or `nil` if no effect exists; only then
/// may it perform its normal checkpoint CAS/receipt read-back transaction.
@MainActor
protocol VoiceProposalDraftCheckpointBridgeV1: AnyObject {
    func existingReviewedVoiceField(
        _ update: VoiceProposalDraftCheckpointUpdateV1
    ) throws -> VoiceProposalDraftCheckpointResultV1?

    func applyReviewedVoiceField(
        _ update: VoiceProposalDraftCheckpointUpdateV1
    ) throws -> VoiceProposalDraftCheckpointResultV1
}

struct VoiceProposalTrustedSnapshotV1: Equatable, Sendable {
    let grammar: VoiceStructuringGrammarReleaseV1
    let context: VoiceProposalContextV1
    let observedAt: Date
    let sourceReferences: [AssistanceSourceReferenceV1]
    /// Optional separately-owned audio scratch. Its lease identity is never
    /// inferred from the proposal ID; ownership is established explicitly.
    let audioScratch: AssistanceCapabilityScratchV1?
    let draftFrontier: VoiceProposalDraftCheckpointFrontierV1
    let generationID: UUID

    init(
        grammar: VoiceStructuringGrammarReleaseV1,
        context: VoiceProposalContextV1,
        observedAt: Date,
        sourceReferences: [AssistanceSourceReferenceV1],
        audioScratch: AssistanceCapabilityScratchV1? = nil,
        draftFrontier: VoiceProposalDraftCheckpointFrontierV1,
        generationID: UUID
    ) throws {
        try grammar.validate()
        try context.validate()
        try sourceReferences.forEach { try $0.validate() }
        guard observedAt.timeIntervalSince1970.isFinite,
              generationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              sourceReferences == Self.sortedSources(sourceReferences),
              Set(sourceReferences).count == sourceReferences.count,
              draftFrontier.workspaceID == context.workspaceID else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        self.grammar = grammar
        self.context = context
        self.observedAt = observedAt
        self.sourceReferences = sourceReferences
        self.audioScratch = audioScratch
        self.draftFrontier = draftFrontier
        self.generationID = generationID
    }

    func validate(for proposal: StructuredVoiceProposalV1) throws {
        try proposal.validate(grammar: grammar)
        try proposal.requireCurrent(at: observedAt, context: context)
        guard draftFrontier.workspaceID == proposal.context.workspaceID,
              audioScratch.map({ $0.proposalID == proposal.proposalID }) ?? true,
              sourceReferences == Self.expectedSources(
                  for: proposal,
                  audioScratch: audioScratch
              ) else {
            throw VoiceStructuringFailureV1.expired
        }
    }

    fileprivate static func sortedSources(
        _ values: [AssistanceSourceReferenceV1]
    ) -> [AssistanceSourceReferenceV1] {
        values.sorted {
            let lhs = "\($0.kind.rawValue)|\($0.sourceID)|\($0.revision)|\($0.contentSHA256)"
            let rhs = "\($1.kind.rawValue)|\($1.sourceID)|\($1.revision)|\($1.contentSHA256)"
            return lhs < rhs
        }
    }

    private static func expectedSources(
        for proposal: StructuredVoiceProposalV1,
        audioScratch: AssistanceCapabilityScratchV1?
    ) -> [AssistanceSourceReferenceV1] {
        var values = [proposal.context.source]
        if let audioScratch {
            values.append(audioScratch.source)
        }
        return sortedSources(values)
    }
}

/// Transcript-free terminal binding retained only for bounded idempotent plan
/// replay. It still forces a fresh trusted snapshot before any plan consumer
/// can read the completed plan.
struct VoiceProposalTerminalBindingV1: Equatable, Sendable {
    let proposalID: UUID
    let proposalSHA256: String
    let grammarID: String
    let grammarVersion: UInt64
    let grammarReleaseSHA256: String
    let context: VoiceProposalContextV1
    let expiresAt: Date
    let sourceReferences: [AssistanceSourceReferenceV1]
    let generationID: UUID

    init(
        proposal: StructuredVoiceProposalV1,
        snapshot: VoiceProposalTrustedSnapshotV1
    ) throws {
        try snapshot.validate(for: proposal)
        proposalID = proposal.proposalID
        proposalSHA256 = try proposal.proposalSHA256
        grammarID = proposal.grammarID
        grammarVersion = proposal.grammarVersion
        grammarReleaseSHA256 = proposal.grammarReleaseSHA256
        context = proposal.context
        expiresAt = proposal.expiresAt
        sourceReferences = snapshot.sourceReferences
        generationID = snapshot.generationID
    }

    func validate(snapshot: VoiceProposalTrustedSnapshotV1) throws {
        guard snapshot.generationID == generationID,
              snapshot.context == context,
              snapshot.grammar.grammarID == grammarID,
              snapshot.grammar.version == grammarVersion,
              (try snapshot.grammar.releaseSHA256) == grammarReleaseSHA256,
              snapshot.sourceReferences == sourceReferences,
              snapshot.observedAt < expiresAt else {
            throw VoiceStructuringFailureV1.expired
        }
    }
}

/// One read supplies grammar, context, time, sources, C36 draft CAS frontier,
/// and generation. The terminal overload deliberately revalidates a plan
/// without retaining its transcript in coordinator memory.
@MainActor
protocol VoiceProposalReviewAuthorityV1: AnyObject {
    func trustedSnapshot(
        for proposal: StructuredVoiceProposalV1
    ) async throws -> VoiceProposalTrustedSnapshotV1

    func trustedSnapshot(
        for terminal: VoiceProposalTerminalBindingV1
    ) async throws -> VoiceProposalTrustedSnapshotV1
}

@MainActor
protocol VoiceProposalScratchCleaningV1: AnyObject {
    /// The proposal ID covers audio scratch with no durable reference; sources
    /// enumerate every nested capability-owned scratch reference.
    func discardVoiceProposalScratch(
        proposalID: UUID,
        sourceReferences: [AssistanceSourceReferenceV1]
    ) async throws
}

/// In-memory, per-field C56 review. There is intentionally no bulk acceptance
/// or direct writer call: each accepted/edited field crosses only the C36 CAS
/// bridge, while rejected fields remain nonpersistent.
@MainActor
final class VoiceProposalReviewCoordinatorV1 {
    private static let maximumActiveEntries = 128
    private static let maximumTerminalEntries = 256

    private struct Entry {
        let proposal: StructuredVoiceProposalV1
        let proposalSHA256: String
        let generationID: UUID
        let sourceReferences: [AssistanceSourceReferenceV1]
        /// The begin-time C36 frontier remains the exact no-write baseline for
        /// an all-reject plan; rejecting fields must not hide an external C36
        /// draft advance before finalization.
        let initialFrontier: VoiceProposalDraftCheckpointFrontierV1
        var reviews: [String: VoiceProposalFieldReviewV1]
        var results: [String: VoiceProposalDraftCheckpointResultV1]
        var latestFrontier: VoiceProposalDraftCheckpointFrontierV1?
    }

    private struct Terminal {
        let proposalSHA256: String
        let workspaceID: WorkspaceID
        let disposition: VoiceProposalTerminalDispositionV1
        let plan: VoiceProposalReviewPlanV1?
        let binding: VoiceProposalTerminalBindingV1?
    }

    private let authority: any VoiceProposalReviewAuthorityV1
    private let draftCheckpointBridge: any VoiceProposalDraftCheckpointBridgeV1
    private let scratchCleaner: any VoiceProposalScratchCleaningV1
    private var entries: [UUID: Entry] = [:]
    private var beginning: [UUID: String] = [:]
    private var cleanupInFlight = Set<UUID>()
    private var cleanupWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private var resettingWorkspaces = Set<WorkspaceID>()
    private var resetCleanupInFlight = Set<WorkspaceID>()
    /// Reset epochs fence re-entrant authority awaits. A completed reset must
    /// still invalidate a begin that captured the preceding generation.
    private var workspaceRevocationEpochs: [WorkspaceID: UInt64] = [:]
    private var terminals: [UUID: Terminal] = [:]
    private var terminalOrder: [UUID] = []

    init(
        authority: any VoiceProposalReviewAuthorityV1,
        draftCheckpointBridge: any VoiceProposalDraftCheckpointBridgeV1,
        scratchCleaner: any VoiceProposalScratchCleaningV1
    ) {
        self.authority = authority
        self.draftCheckpointBridge = draftCheckpointBridge
        self.scratchCleaner = scratchCleaner
    }

    func begin(proposal: StructuredVoiceProposalV1) async throws {
        try proposal.validate()
        guard !resettingWorkspaces.contains(proposal.context.workspaceID) else {
            throw VoiceProposalReviewCoordinatorFailureV1.cleanupInProgress
        }
        let admissionEpoch = workspaceRevocationEpochs[proposal.context.workspaceID, default: 0]
        let digest = try proposal.proposalSHA256
        if let terminal = terminals[proposal.proposalID] {
            guard terminal.proposalSHA256 == digest else {
                throw VoiceProposalReviewCoordinatorFailureV1.divergentProposalReplay
            }
            throw VoiceProposalReviewCoordinatorFailureV1.terminalizedProposal
        }
        if let existing = entries[proposal.proposalID] {
            guard existing.proposalSHA256 == digest else {
                throw VoiceProposalReviewCoordinatorFailureV1.divergentProposalReplay
            }
            let snapshot = try await revalidate(
                proposal: existing.proposal,
                expectedGeneration: existing.generationID
            )
            guard checkedEntry(
                proposalID: proposal.proposalID,
                proposalSHA256: digest,
                generationID: snapshot.generationID
            ) != nil else {
                try await revokeStaleEntry(proposalID: proposal.proposalID)
                throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
            }
            return
        }
        if let pending = beginning[proposal.proposalID] {
            guard pending == digest else {
                throw VoiceProposalReviewCoordinatorFailureV1.divergentProposalReplay
            }
            throw VoiceProposalReviewCoordinatorFailureV1.reviewInProgress
        }
        guard hasAdmissionCapacity(for: proposal.proposalID) else {
            throw VoiceProposalReviewCoordinatorFailureV1.activeProposalLimitExceeded
        }
        beginning[proposal.proposalID] = digest
        defer { beginning.removeValue(forKey: proposal.proposalID) }
        do {
            let snapshot = try await revalidate(proposal: proposal, expectedGeneration: nil)
            guard beginning[proposal.proposalID] == digest,
                  entries[proposal.proposalID] == nil,
                  !cleanupInFlight.contains(proposal.proposalID),
                  !resettingWorkspaces.contains(proposal.context.workspaceID),
                  workspaceRevocationEpochs[proposal.context.workspaceID, default: 0] == admissionEpoch else {
                try await cleanupUnregistered(proposal, snapshot: snapshot, disposition: .erasedOrReset)
                throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
            }
            entries[proposal.proposalID] = Entry(
                proposal: proposal,
                proposalSHA256: digest,
                generationID: snapshot.generationID,
                sourceReferences: snapshot.sourceReferences,
                initialFrontier: snapshot.draftFrontier,
                reviews: [:],
                results: [:],
                latestFrontier: nil
            )
        } catch let failure as VoiceStructuringFailureV1 {
            if failure == .expired || failure == .incompatibleGrammar {
                try await cleanupUnregistered(proposal, disposition: .expired)
            }
            throw failure
        }
    }

    /// Applies exactly one explicit decision. `.accept` requires an exact
    /// parse; ambiguity must be edited or rejected. A bridge result is read
    /// back before any write, then validated as an exact C36 successor.
    func reviewField(
        proposalID: UUID,
        review: VoiceProposalFieldReviewV1
    ) async throws -> VoiceProposalDraftCheckpointResultV1? {
        guard let initial = entries[proposalID] else {
            throw VoiceProposalReviewCoordinatorFailureV1.proposalNotFound
        }
        let snapshot = try await revalidate(
            proposal: initial.proposal,
            expectedGeneration: initial.generationID
        )
        guard var entry = checkedEntry(
            proposalID: proposalID,
            proposalSHA256: initial.proposalSHA256,
            generationID: snapshot.generationID
        ) else {
            try await revokeStaleEntry(proposalID: proposalID)
            throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
        }
        guard let field = entry.proposal.fields.first(where: { $0.fieldID == review.fieldID }) else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        try validate(
            review: review,
            for: field,
            proposal: entry.proposal,
            grammar: snapshot.grammar
        )
        if let existing = entry.reviews[review.fieldID] {
            guard existing == review else {
                throw VoiceProposalReviewCoordinatorFailureV1.divergentFieldReplay
            }
            return entry.results[review.fieldID]
        }
        guard entry.latestFrontier == nil || entry.latestFrontier == snapshot.draftFrontier else {
            throw VoiceStructuringFailureV1.expired
        }

        let result: VoiceProposalDraftCheckpointResultV1?
        switch review.disposition {
        case .reject:
            result = nil
        case .accept, .edit:
            let update = try VoiceProposalDraftCheckpointUpdateV1(
                proposal: entry.proposal,
                field: field,
                review: review,
                snapshot: snapshot
            )
            guard checkedEntry(
                proposalID: proposalID,
                proposalSHA256: entry.proposalSHA256,
                generationID: snapshot.generationID
            ) != nil else {
                try await revokeStaleEntry(proposalID: proposalID)
                throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
            }
            if let replay = try draftCheckpointBridge.existingReviewedVoiceField(update) {
                try validate(
                    replay: replay,
                    for: update,
                    proposal: entry.proposal,
                    grammar: snapshot.grammar
                )
                result = replay
            } else {
                let applied = try draftCheckpointBridge.applyReviewedVoiceField(update)
                try validate(
                    replay: applied,
                    for: update,
                    proposal: entry.proposal,
                    grammar: snapshot.grammar
                )
                result = applied
            }
        }
        entry.reviews[review.fieldID] = review
        if let result {
            entry.results[review.fieldID] = result
            entry.latestFrontier = try result.frontier()
        }
        entries[proposalID] = entry
        return result
    }

    /// Two-phase terminal closure: revalidate all authority, prove every
    /// accepted/edit field has its receipt plus read-back successor, construct
    /// the closed plan, delete scratch, remove active state, then expose it.
    func finalize(proposalID: UUID) async throws -> VoiceProposalReviewPlanV1 {
        guard let initial = entries[proposalID] else {
            if let terminal = terminals[proposalID], terminal.plan != nil {
                guard let plan = try await reviewPlan(proposalID: proposalID) else {
                    throw VoiceProposalReviewCoordinatorFailureV1.proposalNotFound
                }
                return plan
            }
            throw VoiceProposalReviewCoordinatorFailureV1.proposalNotFound
        }
        let snapshot = try await revalidate(
            proposal: initial.proposal,
            expectedGeneration: initial.generationID
        )
        guard let entry = checkedEntry(
            proposalID: proposalID,
            proposalSHA256: initial.proposalSHA256,
            generationID: snapshot.generationID
        ) else {
            try await revokeStaleEntry(proposalID: proposalID)
            throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
        }
        let completionWorkspaceID = entry.proposal.context.workspaceID
        let completionEpoch = workspaceRevocationEpochs[completionWorkspaceID, default: 0]
        // A written review owns the latest successor frontier. An all-reject
        // plan owns no C36 write, so it must still close on the exact frontier
        // observed when review began.
        guard snapshot.draftFrontier == (entry.latestFrontier ?? entry.initialFrontier) else {
            try await revokeStaleEntry(proposalID: proposalID)
            throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
        }
        guard entry.reviews.count == entry.proposal.fields.count else {
            throw VoiceProposalReviewCoordinatorFailureV1.incompleteReview
        }
        for review in entry.reviews.values where review.disposition == .accept || review.disposition == .edit {
            guard entry.results[review.fieldID] != nil else {
                throw VoiceProposalReviewCoordinatorFailureV1.incompleteReview
            }
        }
        let reviews = try entry.proposal.fields.map { field -> VoiceProposalFieldReviewV1 in
            guard let review = entry.reviews[field.fieldID] else {
                throw VoiceProposalReviewCoordinatorFailureV1.incompleteReview
            }
            return review
        }
        let plan = try VoiceProposalReviewPlanV1(
            proposal: entry.proposal,
            fieldReviews: reviews,
            reviewedAt: snapshot.observedAt
        )
        let binding = try VoiceProposalTerminalBindingV1(
            proposal: entry.proposal,
            snapshot: snapshot
        )
        guard checkedEntry(
            proposalID: proposalID,
            proposalSHA256: entry.proposalSHA256,
            generationID: snapshot.generationID
        ) != nil else {
            throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
        }
        try await cleanupActive(
            entry,
            disposition: .completed,
            plan: plan,
            binding: binding,
            requiredWorkspaceEpoch: completionEpoch
        )
        guard !resettingWorkspaces.contains(completionWorkspaceID),
              workspaceRevocationEpochs[completionWorkspaceID, default: 0] == completionEpoch else {
            throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
        }
        return plan
    }

    /// Plan consumption is never a stale memory read. Completed plans retain
    /// only transcript-free binding metadata and are revalidated asynchronously.
    func reviewPlan(proposalID: UUID) async throws -> VoiceProposalReviewPlanV1? {
        guard let terminal = terminals[proposalID],
              let plan = terminal.plan,
              let binding = terminal.binding else {
            return nil
        }
        let snapshot = try await authority.trustedSnapshot(for: binding)
        guard !resettingWorkspaces.contains(binding.context.workspaceID) else {
            throw VoiceProposalReviewCoordinatorFailureV1.cleanupInProgress
        }
        try binding.validate(snapshot: snapshot)
        return plan
    }

    func cancel(proposalID: UUID) async throws {
        guard let entry = entries[proposalID] else {
            throw VoiceProposalReviewCoordinatorFailureV1.proposalNotFound
        }
        try await cleanupActive(entry, disposition: .cancelled, plan: nil, binding: nil)
    }

    /// Adapter lifecycle hook for terminal cancellation, workspace Erase, or
    /// generation reset. It never writes a voice record and preserves already
    /// completed C36 field successors.
    func handleWorkspaceEraseOrReset(workspaceID: WorkspaceID) async throws {
        guard resetCleanupInFlight.insert(workspaceID).inserted else {
            throw VoiceProposalReviewCoordinatorFailureV1.cleanupInProgress
        }
        defer { resetCleanupInFlight.remove(workspaceID) }
        let currentEpoch = workspaceRevocationEpochs[workspaceID, default: 0]
        let (nextEpoch, overflow) = currentEpoch.addingReportingOverflow(1)
        guard !overflow else {
            resettingWorkspaces.insert(workspaceID)
            throw VoiceProposalReviewCoordinatorFailureV1.cleanupInProgress
        }
        workspaceRevocationEpochs[workspaceID] = nextEpoch
        resettingWorkspaces.insert(workspaceID)
        let proposalIDs = entries.values.filter {
            $0.proposal.context.workspaceID == workspaceID
        }.map(\.proposal.proposalID).sorted { $0.uuidString < $1.uuidString }
        for proposalID in proposalIDs {
            await joinCleanupIfNeeded(proposalID)
            if let entry = entries[proposalID] {
                try await cleanupActive(entry, disposition: .erasedOrReset, plan: nil, binding: nil)
            }
        }
        for proposalID in terminals.compactMap({
            $0.value.workspaceID == workspaceID ? $0.key : nil
        }) {
            guard let terminal = terminals[proposalID] else { continue }
            retainTerminal(
                proposalID: proposalID,
                terminal: Terminal(
                    proposalSHA256: terminal.proposalSHA256,
                    workspaceID: workspaceID,
                    disposition: .erasedOrReset,
                    plan: nil,
                    binding: nil
                )
            )
        }
        // Deliberately clear the admission gate only after every cleanup and
        // terminal revocation succeeded. A failed pass leaves it closed until
        // a later erase/reset retry completes this method.
        resettingWorkspaces.remove(workspaceID)
    }

    private func revalidate(
        proposal: StructuredVoiceProposalV1,
        expectedGeneration: UUID?
    ) async throws -> VoiceProposalTrustedSnapshotV1 {
        do {
            let snapshot = try await authority.trustedSnapshot(for: proposal)
            try snapshot.validate(for: proposal)
            if let expectedGeneration, snapshot.generationID != expectedGeneration {
                throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
            }
            return snapshot
        } catch let failure as VoiceStructuringFailureV1 {
            if failure == .expired || failure == .incompatibleGrammar,
               let entry = entries[proposal.proposalID] {
                try await cleanupActive(entry, disposition: .expired, plan: nil, binding: nil)
            }
            throw failure
        } catch let failure as VoiceProposalReviewCoordinatorFailureV1 {
            if failure == .staleGeneration,
               let entry = entries[proposal.proposalID] {
                try await cleanupActive(entry, disposition: .generationRevoked, plan: nil, binding: nil)
            }
            throw failure
        }
    }

    private func checkedEntry(
        proposalID: UUID,
        proposalSHA256: String,
        generationID: UUID
    ) -> Entry? {
        guard !cleanupInFlight.contains(proposalID),
              let entry = entries[proposalID],
              entry.proposalSHA256 == proposalSHA256,
              entry.generationID == generationID,
              !resettingWorkspaces.contains(entry.proposal.context.workspaceID) else {
            return nil
        }
        return entry
    }

    /// Counts unique reservation, active, and cleanup identities rather than
    /// adding collection counts, so the admission cap cannot overflow or be
    /// bypassed by re-entrant begin/cleanup interleavings.
    private func hasAdmissionCapacity(for proposalID: UUID) -> Bool {
        var occupied = Set(entries.keys)
        occupied.formUnion(beginning.keys)
        occupied.formUnion(cleanupInFlight)
        return occupied.contains(proposalID) || occupied.count < Self.maximumActiveEntries
    }

    private func revokeStaleEntry(proposalID: UUID) async throws {
        guard let entry = entries[proposalID] else { return }
        try await cleanupActive(entry, disposition: .generationRevoked, plan: nil, binding: nil)
    }

    private func validate(
        replay: VoiceProposalDraftCheckpointResultV1,
        for update: VoiceProposalDraftCheckpointUpdateV1,
        proposal: StructuredVoiceProposalV1,
        grammar: VoiceStructuringGrammarReleaseV1
    ) throws {
        let validated = try VoiceProposalDraftCheckpointResultV1(
            update: update,
            mutation: replay.mutation,
            mutationReceipt: replay.mutationReceipt,
            successor: replay.successor,
            application: replay.application
        )
        guard let field = proposal.fields.first(where: { $0.fieldID == update.fieldID }),
              field.kind == update.fieldKind,
              validated.updateSHA256 == replay.updateSHA256 else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        let review = try VoiceProposalFieldReviewV1(
            fieldID: update.fieldID,
            disposition: update.disposition,
            reviewedValue: update.value
        )
        try VoiceProposalReviewValidationV1.validate(
            review: review,
            field: field,
            proposal: proposal,
            grammar: grammar
        )
    }

    private func cleanupActive(
        _ entry: Entry,
        disposition: VoiceProposalTerminalDispositionV1,
        plan: VoiceProposalReviewPlanV1?,
        binding: VoiceProposalTerminalBindingV1?,
        requiredWorkspaceEpoch: UInt64? = nil
    ) async throws {
        let proposalID = entry.proposal.proposalID
        guard !cleanupInFlight.contains(proposalID) else {
            throw VoiceProposalReviewCoordinatorFailureV1.cleanupInProgress
        }
        cleanupInFlight.insert(proposalID)
        do {
            try await scratchCleaner.discardVoiceProposalScratch(
                proposalID: proposalID,
                sourceReferences: entry.sourceReferences
            )
            let workspaceID = entry.proposal.context.workspaceID
            let completionRevoked = requiredWorkspaceEpoch.map {
                resettingWorkspaces.contains(workspaceID)
                    || workspaceRevocationEpochs[workspaceID, default: 0] != $0
            } ?? false
            entries.removeValue(forKey: proposalID)
            finishCleanup(proposalID)
            retainTerminal(
                proposalID: proposalID,
                terminal: Terminal(
                    proposalSHA256: entry.proposalSHA256,
                    workspaceID: workspaceID,
                    disposition: completionRevoked ? .erasedOrReset : disposition,
                    plan: completionRevoked ? nil : plan,
                    binding: completionRevoked ? nil : binding
                )
            )
            if completionRevoked {
                throw VoiceProposalReviewCoordinatorFailureV1.staleGeneration
            }
        } catch {
            finishCleanup(proposalID)
            throw error
        }
    }

    private func joinCleanupIfNeeded(_ proposalID: UUID) async {
        guard cleanupInFlight.contains(proposalID) else { return }
        await withCheckedContinuation { continuation in
            if cleanupInFlight.contains(proposalID) {
                cleanupWaiters[proposalID, default: []].append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    private func finishCleanup(_ proposalID: UUID) {
        cleanupInFlight.remove(proposalID)
        let waiters = cleanupWaiters.removeValue(forKey: proposalID) ?? []
        waiters.forEach { $0.resume() }
    }

    private func cleanupUnregistered(
        _ proposal: StructuredVoiceProposalV1,
        snapshot: VoiceProposalTrustedSnapshotV1? = nil,
        disposition: VoiceProposalTerminalDispositionV1
    ) async throws {
        try await scratchCleaner.discardVoiceProposalScratch(
            proposalID: proposal.proposalID,
            sourceReferences: snapshot?.sourceReferences ?? [proposal.context.source]
        )
        retainTerminal(
            proposalID: proposal.proposalID,
            terminal: Terminal(
                proposalSHA256: try proposal.proposalSHA256,
                workspaceID: proposal.context.workspaceID,
                disposition: disposition,
                plan: nil,
                binding: nil
            )
        )
    }

    private func retainTerminal(proposalID: UUID, terminal: Terminal) {
        terminalOrder.removeAll { $0 == proposalID }
        terminals[proposalID] = terminal
        terminalOrder.append(proposalID)
        while terminalOrder.count > Self.maximumTerminalEntries {
            terminals.removeValue(forKey: terminalOrder.removeFirst())
        }
    }

    private func validate(
        review: VoiceProposalFieldReviewV1,
        for field: StructuredVoiceFieldProposalV1,
        proposal: StructuredVoiceProposalV1,
        grammar: VoiceStructuringGrammarReleaseV1
    ) throws {
        try VoiceProposalReviewValidationV1.validate(
            review: review,
            field: field,
            proposal: proposal,
            grammar: grammar
        )
    }
}

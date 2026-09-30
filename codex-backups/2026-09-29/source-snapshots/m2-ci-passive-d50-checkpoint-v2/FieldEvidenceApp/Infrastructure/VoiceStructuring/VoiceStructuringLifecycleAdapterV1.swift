import Foundation

/// Opaque lifecycle generations supplied by the production admission reader.
/// They fence permission, audio-route, app-background, protected-data, and
/// workspace Erase/reset changes without declaring a capture/UI runtime.
enum VoiceStructuringLifecycleOperationV1: String, Equatable, Sendable {
    case present
    case review
    case finalize
    case reject
    case cancel
    case expiryCheck
    case failure
    case eraseOrReset
}

struct VoiceStructuringLifecycleAdmissionV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let proposalID: UUID?
    let operation: VoiceStructuringLifecycleOperationV1
    let permissionGenerationID: UUID
    let audioGenerationID: UUID
    let applicationGenerationID: UUID
    let protectedDataGenerationID: UUID
    let eraseGenerationID: UUID

    init(
        workspaceID: WorkspaceID,
        proposalID: UUID?,
        operation: VoiceStructuringLifecycleOperationV1,
        permissionGenerationID: UUID,
        audioGenerationID: UUID,
        applicationGenerationID: UUID,
        protectedDataGenerationID: UUID,
        eraseGenerationID: UUID
    ) throws {
        guard (operation == .eraseOrReset) == (proposalID == nil),
              proposalID != Self.zero,
              [permissionGenerationID, audioGenerationID, applicationGenerationID,
               protectedDataGenerationID, eraseGenerationID].allSatisfy({ $0 != Self.zero }) else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        self.workspaceID = workspaceID
        self.proposalID = proposalID
        self.operation = operation
        self.permissionGenerationID = permissionGenerationID
        self.audioGenerationID = audioGenerationID
        self.applicationGenerationID = applicationGenerationID
        self.protectedDataGenerationID = protectedDataGenerationID
        self.eraseGenerationID = eraseGenerationID
    }

    private static let zero = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// The production adapter validates all lifecycle generations atomically.  It
/// is an abstract admission seam only; it does not expose permission prompts,
/// audio capture, UI, or a canonical write surface.
@MainActor
protocol VoiceStructuringLifecycleAdmittingV1: AnyObject {
    func admitVoiceStructuringLifecycle(
        _ admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws
}

enum VoiceStructuringExpiryDispositionV1: Equatable, Sendable {
    case retained
    case expired
    case invalidated
}

enum VoiceStructuringLifecycleFailureV1: Error, Equatable, Sendable {
    case scratchCleanupFailed
}

/// Both the adapter and coordinator use this one forwarding gate. `proposalID`
/// is the exact owner key for all audio scratch; `sourceReferences` enumerate
/// transcript and other capability leases. It intentionally retains no
/// terminal cleanup state: sequential same-ID cleanup is delegated to the
/// capability cleaner, so a later lease can never be suppressed.
@MainActor
private final class VoiceStructuringScratchCleanupGateV1: VoiceProposalScratchCleaningV1 {
    private let base: any VoiceProposalScratchCleaningV1

    init(base: any VoiceProposalScratchCleaningV1) {
        self.base = base
    }

    func discardVoiceProposalScratch(
        proposalID: UUID,
        sourceReferences: [AssistanceSourceReferenceV1]
    ) async throws {
        try await base.discardVoiceProposalScratch(
            proposalID: proposalID,
            sourceReferences: sourceReferences
        )
    }
}

/// Concrete C36 composition for C56. The registered draft codec alone
/// transforms opaque payload bytes; the incumbent coordinator performs the
/// existing checkpoint CAS, journal-backed receipt validation, and read-back.
@MainActor
final class VoiceStructuringDraftCheckpointBridgeV1: VoiceProposalDraftCheckpointBridgeV1 {
    private let drafts: FieldDraftCoordinatorV1
    private let payloadApplying: any VoiceReviewedFieldDraftPayloadApplyingV1

    init(
        drafts: FieldDraftCoordinatorV1,
        payloadApplying: any VoiceReviewedFieldDraftPayloadApplyingV1
    ) {
        self.drafts = drafts
        self.payloadApplying = payloadApplying
    }

    func existingReviewedVoiceField(
        _ update: VoiceProposalDraftCheckpointUpdateV1
    ) throws -> VoiceProposalDraftCheckpointResultV1? {
        let application = try application(for: update)
        guard let effect = try drafts.existingReviewedVoiceFieldEffect(
            update,
            application: application
        ) else {
            return nil
        }
        return try result(update: update, effect: effect)
    }

    func applyReviewedVoiceField(
        _ update: VoiceProposalDraftCheckpointUpdateV1
    ) throws -> VoiceProposalDraftCheckpointResultV1 {
        let application = try application(for: update)
        let effect = try drafts.applyReviewedVoiceFieldEffect(
            update,
            application: application
        )
        return try result(update: update, effect: effect)
    }

    private func result(
        update: VoiceProposalDraftCheckpointUpdateV1,
        effect: VoiceReviewedFieldDraftCheckpointEffectV1
    ) throws -> VoiceProposalDraftCheckpointResultV1 {
        try effect.application.validate(predecessor: update.predecessor)
        try payloadApplying.validateReviewedVoiceFieldApplication(
            effect.application,
            predecessor: update.predecessor
        )
        let application = try VoiceProposalDraftCheckpointApplicationV1(
            fieldID: effect.application.fieldID,
            fieldKind: effect.application.fieldKind,
            value: effect.application.value,
            successorPayloadSHA256: effect.application.successorPayloadSHA256
        )
        return try VoiceProposalDraftCheckpointResultV1(
            update: update,
            mutation: effect.mutation,
            mutationReceipt: effect.mutationReceipt,
            successor: effect.successor,
            application: application
        )
    }

    private func application(
        for update: VoiceProposalDraftCheckpointUpdateV1
    ) throws -> VoiceReviewedFieldDraftPayloadApplicationV1 {
        guard payloadApplying.registeredCodec == update.predecessor.codec else {
            throw FieldDraftFailureV1.unknownCodec
        }
        let application = try payloadApplying.applyReviewedVoiceField(
            to: update.predecessor,
            fieldID: update.fieldID,
            fieldKind: update.fieldKind,
            value: update.value
        )
        try application.validate(predecessor: update.predecessor)
        try payloadApplying.validateReviewedVoiceFieldApplication(
            application,
            predecessor: update.predecessor
        )
        return application
    }
}

/// C56's nonpersistent lifecycle facade. The review coordinator remains the
/// only owner of proposal/review-plan memory, C36 checkpoint sequencing, and
/// capability scratch cleanup; this adapter adds no second proposal store.
@MainActor
final class VoiceStructuringLifecycleAdapterV1 {
    private let reviewCoordinator: VoiceProposalReviewCoordinatorV1
    private let admission: any VoiceStructuringLifecycleAdmittingV1
    private let authenticator: any VoiceStructuredProposalAuthenticatingV1
    private let scratchCleaner: VoiceStructuringScratchCleanupGateV1
    private var activeBindings: [UUID: ActiveBinding] = [:]

    private struct ActiveBinding {
        let workspaceID: WorkspaceID
        let proposalSHA256: String
    }

    /// The three injected ports deliberately stop at the existing C32 source
    /// authority and C36 draft checkpoint bridge.  They expose neither an
    /// audio runtime nor a canonical writer.
    init(
        trustedState: any VoiceProposalReviewAuthorityV1,
        drafts: FieldDraftCoordinatorV1,
        payloadApplying: any VoiceReviewedFieldDraftPayloadApplyingV1,
        scratchCleaner: any VoiceProposalScratchCleaningV1,
        admission: any VoiceStructuringLifecycleAdmittingV1,
        authenticator: any VoiceStructuredProposalAuthenticatingV1
    ) {
        let cleanupGate = VoiceStructuringScratchCleanupGateV1(base: scratchCleaner)
        reviewCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: trustedState,
            draftCheckpointBridge: VoiceStructuringDraftCheckpointBridgeV1(
                drafts: drafts,
                payloadApplying: payloadApplying
            ),
            scratchCleaner: cleanupGate
        )
        self.admission = admission
        self.authenticator = authenticator
        self.scratchCleaner = cleanupGate
    }

    /// Registers an exact, grammar-validated proposal for explicit review.
    /// The coordinator obtains one trusted snapshot and fences any late
    /// generation before retaining in-memory proposal bytes.
    func present(
        _ proposal: StructuredVoiceProposalV1,
        admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws {
        let proposalSHA256: String
        do {
            try proposal.validate()
            try validate(admission: admission, proposal: proposal, operation: .present)
            try await self.admission.admitVoiceStructuringLifecycle(admission)
            try authenticator.validateDeterministicProposal(proposal)
            proposalSHA256 = try proposal.proposalSHA256
        } catch {
            do {
                try await scratchCleaner.discardVoiceProposalScratch(
                    proposalID: proposal.proposalID,
                    sourceReferences: [proposal.context.source]
                )
            } catch {
                throw VoiceStructuringLifecycleFailureV1.scratchCleanupFailed
            }
            throw error
        }
        // `begin` owns all post-handoff terminal cleanup, including expiry,
        // generation invalidation, and terminal replay; propagate its error.
        try await reviewCoordinator.begin(proposal: proposal)
        activeBindings[proposal.proposalID] = ActiveBinding(
            workspaceID: proposal.context.workspaceID,
            proposalSHA256: proposalSHA256
        )
    }

    /// Applies one explicit field decision.  Accepted and edited values cross
    /// only the narrow C36 bridge; reject is an in-memory field decision.
    @discardableResult
    func review(
        proposalID: UUID,
        fieldReview: VoiceProposalFieldReviewV1,
        admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws -> VoiceProposalDraftCheckpointResultV1? {
        try await admit(proposalID: proposalID, admission: admission, operation: .review)
        do {
            return try await reviewCoordinator.reviewField(
                proposalID: proposalID,
                review: fieldReview
            )
        } catch {
            try removeTerminalBindingIfNeeded(proposalID: proposalID, error: error)
            throw error
        }
    }

    /// Closes a fully reviewed proposal.  Completion removes active proposal
    /// memory and capability scratch before returning the transcript-free plan.
    func finalizeReview(
        proposalID: UUID,
        admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws -> VoiceProposalReviewPlanV1 {
        try await admit(proposalID: proposalID, admission: admission, operation: .finalize)
        do {
            let plan = try await reviewCoordinator.finalize(proposalID: proposalID)
            activeBindings.removeValue(forKey: proposalID)
            return plan
        } catch {
            try removeTerminalBindingIfNeeded(proposalID: proposalID, error: error)
            throw error
        }
    }

    /// Revalidates the completed plan against a fresh trusted snapshot before
    /// exposing its bounded, transcript-free terminal replay value.
    func reviewPlan(proposalID: UUID) async throws -> VoiceProposalReviewPlanV1? {
        try await reviewCoordinator.reviewPlan(proposalID: proposalID)
    }

    /// Discards an entire proposal after a user rejects it.  Field-level
    /// rejects remain available through `review`; this terminal operation
    /// clears the remaining proposal state and all capability scratch.
    func reject(
        proposalID: UUID,
        admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws {
        try await admit(proposalID: proposalID, admission: admission, operation: .reject)
        try await reviewCoordinator.cancel(proposalID: proposalID)
        activeBindings.removeValue(forKey: proposalID)
    }

    /// Cancels an active proposal without undoing any prior C36 checkpoints.
    func cancel(
        proposalID: UUID,
        admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws {
        try await admit(proposalID: proposalID, admission: admission, operation: .cancel)
        try await reviewCoordinator.cancel(proposalID: proposalID)
        activeBindings.removeValue(forKey: proposalID)
    }

    /// Revalidates an active proposal.  A current proposal remains active;
    /// exact expiry and grammar invalidation terminalize it and clear scratch.
    func expireIfNeeded(
        _ proposal: StructuredVoiceProposalV1,
        admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws -> VoiceStructuringExpiryDispositionV1 {
        try proposal.validate()
        guard let binding = activeBindings[proposal.proposalID],
              binding.workspaceID == proposal.context.workspaceID,
              binding.proposalSHA256 == (try proposal.proposalSHA256) else {
            throw VoiceProposalReviewCoordinatorFailureV1.proposalNotFound
        }
        try validate(admission: admission, proposal: proposal, operation: .expiryCheck)
        try await self.admission.admitVoiceStructuringLifecycle(admission)
        do {
            try await reviewCoordinator.begin(proposal: proposal)
            return .retained
        } catch let error as VoiceStructuringFailureV1 {
            switch error {
            case .expired:
                activeBindings.removeValue(forKey: proposal.proposalID)
                return .expired
            case .incompatibleGrammar:
                activeBindings.removeValue(forKey: proposal.proposalID)
                return .invalidated
            default:
                throw error
            }
        } catch let error as VoiceProposalReviewCoordinatorFailureV1 {
            if error == .staleGeneration {
                activeBindings.removeValue(forKey: proposal.proposalID)
            }
            throw error
        }
    }

    /// Terminalizes an active proposal after an external lifecycle failure.
    /// The coordinator performs the sole cleanup, so retryable C36 failures
    /// can instead remain active and recover through their idempotent bridge.
    func fail(
        proposalID: UUID,
        admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws {
        try await admit(proposalID: proposalID, admission: admission, operation: .failure)
        try await reviewCoordinator.cancel(proposalID: proposalID)
        activeBindings.removeValue(forKey: proposalID)
    }

    /// Erase and generation-reset handling is workspace-scoped.  It clears
    /// every active proposal and its scratch while retaining no voice record,
    /// journal entry, backup payload, search projection, or report data.
    func handleWorkspaceEraseOrReset(
        workspaceID: WorkspaceID,
        admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws {
        guard admission.workspaceID == workspaceID,
              admission.proposalID == nil,
              admission.operation == .eraseOrReset else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        try await self.admission.admitVoiceStructuringLifecycle(admission)
        try await reviewCoordinator.handleWorkspaceEraseOrReset(workspaceID: workspaceID)
        activeBindings = activeBindings.filter { $0.value.workspaceID != workspaceID }
    }

    private func admit(
        proposalID: UUID,
        admission: VoiceStructuringLifecycleAdmissionV1,
        operation: VoiceStructuringLifecycleOperationV1
    ) async throws {
        guard let binding = activeBindings[proposalID],
              admission.workspaceID == binding.workspaceID,
              admission.proposalID == proposalID,
              admission.operation == operation else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        try await self.admission.admitVoiceStructuringLifecycle(admission)
    }

    private func validate(
        admission: VoiceStructuringLifecycleAdmissionV1,
        proposal: StructuredVoiceProposalV1,
        operation: VoiceStructuringLifecycleOperationV1
    ) throws {
        guard admission.workspaceID == proposal.context.workspaceID,
              admission.proposalID == proposal.proposalID,
              admission.operation == operation else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }

    private func removeTerminalBindingIfNeeded(
        proposalID: UUID,
        error: Error
    ) throws {
        if let failure = error as? VoiceStructuringFailureV1,
           failure == .expired || failure == .incompatibleGrammar {
            activeBindings.removeValue(forKey: proposalID)
            return
        }
        if let failure = error as? VoiceProposalReviewCoordinatorFailureV1,
           failure == .staleGeneration {
            activeBindings.removeValue(forKey: proposalID)
        }
    }
}

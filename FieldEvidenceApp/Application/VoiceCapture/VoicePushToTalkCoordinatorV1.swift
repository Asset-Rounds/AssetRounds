import Foundation

/// Narrow C45 view of C56. It deliberately exposes no writer and retains C56
/// as the sole owner of proposal/review-plan memory and checkpoints.
@MainActor
protocol VoicePushToTalkReviewingV1: AnyObject {
    func present(_ proposal: StructuredVoiceProposalV1, admission: VoiceStructuringLifecycleAdmissionV1) async throws
    func review(proposalID: UUID, fieldReview: VoiceProposalFieldReviewV1, admission: VoiceStructuringLifecycleAdmissionV1) async throws -> VoiceProposalDraftCheckpointResultV1?
    func finalizeReview(proposalID: UUID, admission: VoiceStructuringLifecycleAdmissionV1) async throws -> VoiceProposalReviewPlanV1
    func reject(proposalID: UUID, admission: VoiceStructuringLifecycleAdmissionV1) async throws
    func cancel(proposalID: UUID, admission: VoiceStructuringLifecycleAdmissionV1) async throws
}

extension VoiceStructuringLifecycleAdapterV1: VoicePushToTalkReviewingV1 {}

/// C45's single-session, nonpersistent capture coordinator. It delegates
/// canonical proposal review to C56 and never invokes a writer directly.
@MainActor
final class VoicePushToTalkCoordinatorV1 {
    enum Outcome: Equatable, Sendable {
        case capturing(sessionID: UUID)
        case manualFallback(VoiceCaptureManualFallbackReasonV1)
        case proposal(StructuredVoiceProposalV1)
        case cleaned(VoiceScratchDispositionV1)
        case terminalCancellationPending(VoiceScratchDispositionV1)
        case presentationTerminalPending(VoiceScratchDispositionV1)
    }

    private struct CleanupRequest: Equatable {
        let disposition: VoiceScratchDispositionV1
        let preservingSource: AssistanceSourceReferenceV1?
    }

    private struct ActiveSession {
        let context: StructuredVoiceCaptureContextV1
        var lastCallbackSequence: UInt64
        var proposal: StructuredVoiceProposalV1?
        var captureClosed: Bool
        var cleanupPending: CleanupRequest?
        var completedCleanup: CleanupRequest?
        var retryableCleanup: CleanupRequest?
        var terminalCancellation: VoiceScratchDispositionV1?
        var presentationInFlight: Bool
        var deferredTerminal: VoiceScratchDispositionV1?
    }

    private let capture: any StructuredVoiceCapturePortV1
    private let scratch: any StructuredVoiceScratchLifecycleV1
    private let structuring: VoiceStructuringServiceV1
    private let review: any VoicePushToTalkReviewingV1
    private var active: ActiveSession?

    init(capture: any StructuredVoiceCapturePortV1,
         scratch: any StructuredVoiceScratchLifecycleV1,
         structuring: VoiceStructuringServiceV1,
         review: any VoicePushToTalkReviewingV1) {
        self.capture = capture
        self.scratch = scratch
        self.structuring = structuring
        self.review = review
    }

    func start(_ context: StructuredVoiceCaptureContextV1) async throws -> Outcome {
        try context.validate()
        guard active == nil else { throw VoiceCaptureFailureV1.sessionAlreadyActive }
        active = ActiveSession(context: context, lastCallbackSequence: 0, proposal: nil,
                               captureClosed: false, cleanupPending: nil, completedCleanup: nil,
                               retryableCleanup: nil, terminalCancellation: nil,
                               presentationInFlight: false, deferredTerminal: nil)
        do {
            try await capture.beginPushToTalkCapture(context)
            return .capturing(sessionID: context.sessionID)
        } catch {
            // A port may have activated audio before reporting failure.
            closeCapture()
            await capture.cancelPushToTalkCapture(sessionID: context.sessionID)
            try await clean(disposition: .failed, preservingSource: nil)
            active = nil
            throw error
        }
    }

    func stop(sessionID: UUID) async throws {
        let context = try requireCapturing(sessionID)
        try await capture.stopPushToTalkCapture(sessionID: context.sessionID)
    }

    func cancel(sessionID: UUID) async throws -> Outcome {
        _ = try requireCapturing(sessionID)
        closeCapture()
        await capture.cancelPushToTalkCapture(sessionID: sessionID)
        try await clean(disposition: .cancelled, preservingSource: nil)
        active = nil
        return .cleaned(.cancelled)
    }

    func applicationDidEnterBackground() async throws -> Outcome { try await terminate(.backgrounded) }
    func audioInterrupted() async throws -> Outcome { try await terminate(.interrupted) }
    func permissionRevoked() async throws -> Outcome { try await terminate(.permissionRevoked) }

    func receive(_ event: StructuredVoiceCaptureEventV1,
                 currentTargetRevision: UInt64) async throws -> Outcome {
        let (sessionID, generation, digest, sequence) = metadata(of: event)
        let context = try requireCapturing(sessionID)
        guard currentTargetRevision == context.targetRevision else {
            try await terminate(.stale)
            throw VoiceCaptureFailureV1.staleCallback
        }
        guard context.lifecycleGeneration == generation, context.contextSHA256 == digest,
              sequence > (active?.lastCallbackSequence ?? .max) else {
            throw VoiceCaptureFailureV1.staleCallback
        }
        active?.lastCallbackSequence = sequence
        switch event {
        case .failed(_, _, _, _, let fallback):
            closeCapture()
            await capture.cancelPushToTalkCapture(sessionID: sessionID)
            try await clean(disposition: Self.disposition(for: fallback), preservingSource: nil)
            active = nil
            return .manualFallback(fallback)
        case .final(let captured):
            closeCapture() // final/late callbacks can never reopen capture.
            let proposal: StructuredVoiceProposalV1
            do {
                try captured.validate()
                guard captured.durationSeconds <= context.maximumDurationSeconds,
                      captured.processedOnDevice, !captured.networkAccessUsed else {
                    throw VoiceCaptureFailureV1.captureRejected
                }
                proposal = try structuring.structure(
                    transcript: captured.transcript,
                    context: try context.proposalContext(source: captured.source)
                )
                guard var presenting = active,
                      presenting.context.sessionID == context.sessionID,
                      presenting.context.contextSHA256 == context.contextSHA256,
                      presenting.context.targetRevision == context.targetRevision,
                      presenting.context.lifecycleGeneration == context.lifecycleGeneration else {
                    throw VoiceCaptureFailureV1.staleCallback
                }
                presenting.proposal = proposal
                presenting.presentationInFlight = true
                active = presenting
                try await review.present(
                    proposal,
                    admission: try context.lifecycleAdmission(proposalID: proposal.proposalID, operation: .present)
                )
            } catch {
                await capture.cancelPushToTalkCapture(sessionID: sessionID)
                if var failedPresentation = active,
                   failedPresentation.context.sessionID == context.sessionID {
                    // C56 `present` owns its failed-source cleanup. Keep only
                    // retryable C45 audio cleanup; never retain review state.
                    failedPresentation.proposal = nil
                    failedPresentation.presentationInFlight = false
                    failedPresentation.deferredTerminal = nil
                    failedPresentation.terminalCancellation = nil
                    active = failedPresentation
                }
                do {
                    try await clean(disposition: .failed, preservingSource: nil)
                } catch {
                    throw VoiceCaptureFailureV1.scratchCleanupFailed
                }
                active = nil
                if error is VoiceCaptureFailureV1 { throw error }
                throw VoiceCaptureFailureV1.structuringFailed
            }
            guard var resumed = active,
                  resumed.context.sessionID == context.sessionID,
                  resumed.context.contextSHA256 == context.contextSHA256,
                  resumed.context.targetRevision == context.targetRevision,
                  resumed.context.lifecycleGeneration == context.lifecycleGeneration,
                  resumed.proposal == proposal,
                  resumed.presentationInFlight else {
                return try await recoverAfterPresentationFenceMismatch(
                    context: context,
                    proposal: proposal
                )
            }
            resumed.presentationInFlight = false
            active = resumed
            if let deferred = resumed.deferredTerminal {
                return try await finishDeferredTerminal(deferred)
            }
            do {
                // The source now belongs to C56 until reject/cancel/finalize.
                try await clean(disposition: .captureAudioDiscarded,
                                preservingSource: proposal.context.source)
            } catch {
                // C56 is already presenting this proposal; retain it and the
                // retryable C45 cleanup state rather than deleting its source.
                throw VoiceCaptureFailureV1.scratchCleanupFailed
            }
            return .proposal(proposal)
        }
    }

    /// Explicit accept/edit alone can checkpoint through C56. Reject remains
    /// a review decision and returns nil from C56, preserving zero-write.
    func reviewField(_ fieldReview: VoiceProposalFieldReviewV1,
                     currentTargetRevision: UInt64) async throws -> VoiceProposalDraftCheckpointResultV1? {
        let (active, proposal) = try await requireProposal(currentTargetRevision: currentTargetRevision)
        return try await review.review(proposalID: proposal.proposalID, fieldReview: fieldReview,
                                       admission: try active.context.lifecycleAdmission(proposalID: proposal.proposalID, operation: .review))
    }

    func finalizeReview(currentTargetRevision: UInt64) async throws -> VoiceProposalReviewPlanV1 {
        let (active, proposal) = try await requireProposal(currentTargetRevision: currentTargetRevision)
        let plan = try await review.finalizeReview(proposalID: proposal.proposalID,
                                                   admission: try active.context.lifecycleAdmission(proposalID: proposal.proposalID, operation: .finalize))
        self.active = nil
        return plan
    }

    func rejectProposal(currentTargetRevision: UInt64) async throws {
        let (active, proposal) = try await requireProposal(currentTargetRevision: currentTargetRevision)
        try await review.reject(proposalID: proposal.proposalID,
                                admission: try active.context.lifecycleAdmission(proposalID: proposal.proposalID, operation: .reject))
        self.active = nil
    }

    /// The draft host calls this whenever its CAS target advances. A changed
    /// target cannot receive late capture callbacks or proposal review.
    func targetRevisionDidChange(_ currentTargetRevision: UInt64) async throws -> Outcome? {
        guard let active else { return nil }
        guard currentTargetRevision != active.context.targetRevision else { return nil }
        return try await terminate(.stale)
    }

    /// Re-attempts only a failed C45 scratch finalization. A proposal keeps
    /// its exact leased transcript source preserved for C56 while this retry
    /// discards temporary capture audio.
    func retryScratchCleanup() async throws -> Outcome {
        guard let active, active.completedCleanup == nil else {
            throw VoiceCaptureFailureV1.noActiveSession
        }
        guard !active.presentationInFlight, active.deferredTerminal == nil else {
            throw VoiceCaptureFailureV1.presentationInFlight
        }
        guard let request = active.retryableCleanup else {
            throw VoiceCaptureFailureV1.cleanupInProgress
        }
        try await clean(disposition: request.disposition, preservingSource: request.preservingSource)
        guard let current = self.active else { throw VoiceCaptureFailureV1.noActiveSession }
        if let terminal = current.terminalCancellation {
            return .terminalCancellationPending(terminal)
        }
        if let proposal = current.proposal { return .proposal(proposal) }
        self.active = nil
        return .cleaned(request.disposition)
    }

    /// Retries the exact C56 cancellation that previously failed. It is
    /// admitted with the original lifecycle fence and cannot report a terminal
    /// outcome until C56 has accepted cancellation of its preserved source.
    func retryTerminalCancellation() async throws -> Outcome {
        guard let active, let disposition = active.terminalCancellation,
              let proposal = active.proposal else {
            throw VoiceCaptureFailureV1.noActiveSession
        }
        guard !active.presentationInFlight, active.deferredTerminal == nil else {
            throw VoiceCaptureFailureV1.presentationInFlight
        }
        guard active.cleanupPending == nil, active.retryableCleanup == nil,
              let completed = active.completedCleanup,
              completed.disposition == .captureAudioDiscarded,
              completed.preservingSource == proposal.context.source else {
            throw VoiceCaptureFailureV1.cleanupInProgress
        }
        do {
            try await review.cancel(
                proposalID: proposal.proposalID,
                admission: try active.context.lifecycleAdmission(
                    proposalID: proposal.proposalID, operation: .cancel
                )
            )
        } catch {
            throw VoiceCaptureFailureV1.terminalCancellationPending
        }
        guard var cleared = self.active,
              cleared.context.sessionID == active.context.sessionID else {
            throw VoiceCaptureFailureV1.terminalCancellationPending
        }
        cleared.proposal = nil
        cleared.terminalCancellation = nil
        self.active = cleared
        self.active = nil
        return .manualFallback(Self.fallback(for: disposition))
    }

    private func terminate(_ disposition: VoiceScratchDispositionV1) async throws -> Outcome {
        guard let active else { throw VoiceCaptureFailureV1.noActiveSession }
        if active.presentationInFlight {
            closeCapture()
            guard var deferred = self.active,
                  deferred.context.sessionID == active.context.sessionID else {
                throw VoiceCaptureFailureV1.presentationInFlight
            }
            // The first terminal cause fences this presentation. C56 cannot be
            // cancelled until its awaited `present` call has returned.
            if deferred.deferredTerminal == nil { deferred.deferredTerminal = disposition }
            self.active = deferred
            await capture.cancelPushToTalkCapture(sessionID: active.context.sessionID)
            return .presentationTerminalPending(deferred.deferredTerminal ?? disposition)
        }
        closeCapture()
        await capture.cancelPushToTalkCapture(sessionID: active.context.sessionID)
        var cancellationError: Error?
        do { try await cancelProposalIfPresent(active) } catch { cancellationError = error }
        guard var afterCancellation = self.active,
              afterCancellation.context.sessionID == active.context.sessionID else {
            throw VoiceCaptureFailureV1.terminalCancellationPending
        }
        if cancellationError == nil {
            // C56 terminalized and cleaned its source, so C45 retains no
            // proposal that a later scratch retry could expose for review.
            afterCancellation.proposal = nil
            afterCancellation.terminalCancellation = nil
        } else {
            afterCancellation.terminalCancellation = disposition
        }
        self.active = afterCancellation
        let cleanup: CleanupRequest
        if cancellationError != nil, let source = afterCancellation.proposal?.context.source {
            // C56 still owns this source until its cancellation succeeds.
            cleanup = CleanupRequest(
                disposition: .captureAudioDiscarded,
                preservingSource: source
            )
        } else {
            cleanup = CleanupRequest(disposition: disposition, preservingSource: nil)
        }
        do {
            try await clean(
                disposition: cleanup.disposition,
                preservingSource: cleanup.preservingSource
            )
        } catch {
            // Cleanup takes precedence, but C56 cancellation was still tried.
            throw VoiceCaptureFailureV1.scratchCleanupFailed
        }
        // A failed C56 cancellation remains explicit and retryable even after
        // C45 audio cleanup succeeds; never expose the proposal for review.
        if cancellationError != nil { throw VoiceCaptureFailureV1.terminalCancellationPending }
        self.active = nil
        return .manualFallback(Self.fallback(for: disposition))
    }

    private func requireCapturing(_ sessionID: UUID) throws -> StructuredVoiceCaptureContextV1 {
        guard let active, active.context.sessionID == sessionID, !active.captureClosed else {
            throw VoiceCaptureFailureV1.noActiveSession
        }
        return active.context
    }

    private func requireProposal(currentTargetRevision: UInt64) async throws -> (ActiveSession, StructuredVoiceProposalV1) {
        guard let active, let proposal = active.proposal else { throw VoiceCaptureFailureV1.noActiveSession }
        guard !active.presentationInFlight, active.deferredTerminal == nil else {
            throw VoiceCaptureFailureV1.presentationInFlight
        }
        guard active.terminalCancellation == nil else {
            throw VoiceCaptureFailureV1.terminalCancellationPending
        }
        guard currentTargetRevision == active.context.targetRevision else {
            _ = try await targetRevisionDidChange(currentTargetRevision)
            throw VoiceCaptureFailureV1.staleCallback
        }
        guard active.cleanupPending == nil, active.retryableCleanup == nil,
              let completed = active.completedCleanup,
              completed.disposition == .captureAudioDiscarded,
              completed.preservingSource == proposal.context.source else {
            throw VoiceCaptureFailureV1.cleanupInProgress
        }
        return (active, proposal)
    }

    /// Defensive recovery for an impossible post-await state divergence. The
    /// returned proposal has already reached C56, so reconstruct a fenced
    /// terminal session and cancel it rather than leaking its source.
    private func recoverAfterPresentationFenceMismatch(
        context: StructuredVoiceCaptureContextV1,
        proposal: StructuredVoiceProposalV1
    ) async throws -> Outcome {
        active = ActiveSession(
            context: context,
            lastCallbackSequence: UInt64.max,
            proposal: proposal,
            captureClosed: true,
            cleanupPending: nil,
            completedCleanup: nil,
            retryableCleanup: nil,
            terminalCancellation: nil,
            presentationInFlight: false,
            deferredTerminal: nil
        )
        return try await terminate(.stale)
    }

    /// Converts a terminal event observed during the C56 presentation await
    /// into the ordinary C56-cancel/C45-cleanup state machine immediately
    /// after presentation is known to have returned.
    private func finishDeferredTerminal(_ disposition: VoiceScratchDispositionV1) async throws -> Outcome {
        guard var active, !active.presentationInFlight,
              active.deferredTerminal == disposition else {
            throw VoiceCaptureFailureV1.presentationInFlight
        }
        active.deferredTerminal = nil
        self.active = active
        return try await terminate(disposition)
    }

    private func closeCapture() {
        guard var active else { return }
        active.captureClosed = true
        self.active = active
    }

    /// Marks a cleanup as pending before awaiting, but marks it complete only
    /// after the scratch lifecycle succeeds. A failed attempt is retryable.
    private func clean(disposition: VoiceScratchDispositionV1,
                       preservingSource: AssistanceSourceReferenceV1?) async throws {
        guard var active else { return }
        if active.completedCleanup != nil { return }
        guard active.cleanupPending == nil else { throw VoiceCaptureFailureV1.cleanupInProgress }
        let request = CleanupRequest(disposition: disposition, preservingSource: preservingSource)
        active.cleanupPending = request
        active.retryableCleanup = nil
        self.active = active
        do {
            try await scratch.discardStructuredVoiceCaptureScratch(
                sessionID: active.context.sessionID, disposition: disposition,
                preservingSource: preservingSource
            )
        } catch {
            guard var retryable = self.active,
                  retryable.context.sessionID == active.context.sessionID else {
                throw VoiceCaptureFailureV1.scratchCleanupFailed
            }
            retryable.cleanupPending = nil
            retryable.retryableCleanup = request
            self.active = retryable
            throw VoiceCaptureFailureV1.scratchCleanupFailed
        }
        guard var completed = self.active,
              completed.context.sessionID == active.context.sessionID else {
            throw VoiceCaptureFailureV1.scratchCleanupFailed
        }
        completed.cleanupPending = nil
        completed.completedCleanup = request
        completed.retryableCleanup = nil
        self.active = completed
    }

    private func cancelProposalIfPresent(_ active: ActiveSession) async throws {
        guard let proposal = active.proposal else { return }
        try await review.cancel(proposalID: proposal.proposalID,
                                admission: try active.context.lifecycleAdmission(proposalID: proposal.proposalID, operation: .cancel))
    }

    private func metadata(of event: StructuredVoiceCaptureEventV1) -> (UUID, VoiceCaptureLifecycleGenerationV1, String, UInt64) {
        switch event {
        case .final(let value): return (value.sessionID, value.lifecycleGeneration, value.contextSHA256, value.callbackSequence)
        case .failed(let sessionID, let generation, let digest, let sequence, _): return (sessionID, generation, digest, sequence)
        }
    }

    private static func disposition(for fallback: VoiceCaptureManualFallbackReasonV1) -> VoiceScratchDispositionV1 {
        switch fallback {
        case .cancelled: return .cancelled
        case .backgrounded: return .backgrounded
        case .interrupted: return .interrupted
        case .permissionRevoked: return .permissionRevoked
        case .permissionDenied, .permissionRestricted, .permissionNotDetermined,
             .unsupportedLocale, .unsupportedDevice, .protectedDataUnavailable,
             .unavailable, .typeManually: return .unavailable
        }
    }

    private static func fallback(for disposition: VoiceScratchDispositionV1) -> VoiceCaptureManualFallbackReasonV1 {
        switch disposition {
        case .backgrounded: return .backgrounded
        case .interrupted: return .interrupted
        case .permissionRevoked: return .permissionRevoked
        case .cancelled: return .cancelled
        case .captureAudioDiscarded, .unavailable, .stale, .failed: return .unavailable
        }
    }
}

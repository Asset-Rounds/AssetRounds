import Foundation

@MainActor final class RatingEligibilityCoordinatorV1 {
    private let policy: RatingEligibilityPolicyV1
    private let store: any RatingEligibilityStoreV1
    private let nativeRequest: any RatingRequestAdapterV1
    private let clock: any ApplicationClock

    init(policy: RatingEligibilityPolicyV1 = .init(),
         store: any RatingEligibilityStoreV1,
         nativeRequest: any RatingRequestAdapterV1,
         clock: any ApplicationClock) throws {
        try policy.validate()
        self.policy = policy; self.store = store
        self.nativeRequest = nativeRequest; self.clock = clock
    }

    /// Produces an exact runtime proof without writing its customer/work
    /// identities to rating storage.
    func recordEligibleCompletion(_ candidate: RatingFinalizedActivityCandidateV1)
        -> RatingCompletionRecordingOutcomeV1 {
        guard let projection = try? RatingEligibleCompletionProjectionV1(candidate: candidate) else {
            return .excluded
        }
        return .eligibleRuntimeProjection(projection)
    }

    func project(completions: [RatingEligibleCompletionProjectionV1],
                 marketingVersion: RatingMarketingVersionV1,
                 buildVersion: RatingBuildVersionV1,
                 naturalStop: RatingNaturalStopV1) async -> RatingEligibilityProjectionV1 {
        do {
            try naturalStop.validate()
            let loaded = try await store.load()
            return evaluate(completions: completions, marketingVersion: marketingVersion,
                            buildVersion: buildVersion,
                            naturalStop: naturalStop, loaded: loaded, now: clock.now())
        } catch {
            return projection(reasons: [.ledgerUnavailable], completions: completions)
        }
    }

    func requestIfEligible(completions: [RatingEligibleCompletionProjectionV1],
                           marketingVersion: RatingMarketingVersionV1,
                           buildVersion: RatingBuildVersionV1,
                           naturalStop: RatingNaturalStopV1,
                           reservationOperationID: UUID,
                           invocationStatusOperationID: UUID) async throws -> RatingRequestOutcomeV1 {
        try naturalStop.validate()
        guard reservationOperationID != UUID.zero,
              invocationStatusOperationID != UUID.zero,
              reservationOperationID != invocationStatusOperationID else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        let loaded = try await store.load()
        let now = clock.now()
        let current: RatingRequestAttemptLedgerStateV1?
        switch loaded {
        case .absentFreshInstall: current = nil
        case .current(let value):
            guard (try? value.validate()) != nil else {
                return .ineligible(projection(reasons: [.ledgerCorrupt], completions: completions))
            }
            current = value
        case .corrupt:
            return .ineligible(projection(reasons: [.ledgerCorrupt], completions: completions))
        case .futureVersion:
            return .ineligible(projection(reasons: [.ledgerFutureVersion], completions: completions))
        case .migrationFailed:
            return .ineligible(projection(reasons: [.ledgerMigrationFailed], completions: completions))
        }
        let idempotencyKey = try WorkspaceMutationCanonicalV1.sha256(IdempotencyBasis(
            eventID: naturalStop.eventID, policySHA256: policy.policySHA256,
            marketingVersion: marketingVersion, buildVersion: buildVersion))
        if let duplicate = current?.attempts.first(where: {
            $0.idempotencyKeySHA256 == idempotencyKey
        }) {
            return .duplicateConservativeAttempt(duplicate)
        }
        let eligibility = evaluate(completions: completions, marketingVersion: marketingVersion,
                                   buildVersion: buildVersion,
                                   naturalStop: naturalStop, loaded: loaded, now: now)
        guard eligibility.eligible else { return .ineligible(eligibility) }
        guard let preparedRequest = nativeRequest.prepareRequest() else {
            let reason: RatingEligibilityReasonV1
            switch nativeRequest.availability {
            case .disabledUnverifiedPlatform:
                reason = .automaticRequestDisabledUnverifiedPlatform
            case .available, .sceneUnavailable:
                reason = .sceneUnavailable
            }
            return .ineligible(.init(eligible: false, reasons: [reason],
                distinctSeriesCount: eligibility.distinctSeriesCount,
                observedSeriesSpanSeconds: eligibility.observedSeriesSpanSeconds,
                supportVisible: true, recoveryVisible: true))
        }

        let reserved = RatingRequestAttemptV1(idempotencyKeySHA256: idempotencyKey,
            policySHA256: try policy.policySHA256, marketingVersion: marketingVersion,
            buildVersion: buildVersion,
            reservedAt: now, nativeInvokedAt: nil, disposition: .reservedBeforeNativeCall)
        try reserved.validate()
        let reservationState = try RatingRequestAttemptLedgerStateV1(
            revision: (current?.revision ?? 0) + 1, origin: current?.origin ?? .established,
            attempts: (current?.attempts ?? []) + [reserved],
            clockHighWatermarkUTC: max(current?.clockHighWatermarkUTC ?? now, now))
        let reservationReceipt = try await store.compareAndSwap(operationID: reservationOperationID,
            expectedRevision: current?.revision, successor: reservationState)
        try validate(reservationReceipt, expectedOperationID: reservationOperationID,
                     expectedRevision: current?.revision, state: reservationState)

        // The reservation is durable before invoking the exact scene capability
        // captured before the persistence suspension.
        let nativeResult = preparedRequest.invoke()
        guard nativeResult == .systemConsiderationRequested else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        let invokedAt = clock.now()
        let invoked = RatingRequestAttemptV1(idempotencyKeySHA256: idempotencyKey,
            policySHA256: try policy.policySHA256, marketingVersion: marketingVersion,
            buildVersion: buildVersion,
            reservedAt: now, nativeInvokedAt: invokedAt, disposition: .nativeRequestInvoked)
        let invokedState = try RatingRequestAttemptLedgerStateV1(
            revision: reservationState.revision + 1, origin: reservationState.origin,
            attempts: reservationState.attempts.map {
                $0.idempotencyKeySHA256 == idempotencyKey ? invoked : $0
            },
            clockHighWatermarkUTC: max(reservationState.clockHighWatermarkUTC, invokedAt))
        do {
            let receipt = try await store.compareAndSwap(operationID: invocationStatusOperationID,
                expectedRevision: reservationState.revision, successor: invokedState)
            try validate(receipt, expectedOperationID: invocationStatusOperationID,
                         expectedRevision: reservationState.revision, state: invokedState)
            return .nativeRequestInvoked(invoked)
        } catch {
            // The conservative reservation continues to suppress all replay.
            return .nativeRequestInvokedStatusPersistencePending(reserved)
        }
    }

    /// Ordinary Settings Reset deliberately performs no store mutation.
    func applySettingsReset() -> RatingResetOutcomeV1 { .preserved }

    /// Called only after Erase has completed its normal defaults-domain wipe.
    /// The replacement contains operation identity and time only, no customer data.
    func applyCompletedErase(eraseOperationID: UUID, erasedAt: Date) async throws
        -> RatingEraseOutcomeV1 {
        guard eraseOperationID != UUID.zero, erasedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        if case .current(let prior) = try await store.load(), prior.attempts.isEmpty,
           case .erasedCooldown(_, let priorUntil) = prior.origin {
            let replay = try await store.compareAndSwap(operationID: eraseOperationID,
                expectedRevision: nil, successor: prior)
            try validate(replay, expectedOperationID: eraseOperationID,
                         expectedRevision: nil, state: prior)
            return .init(receipt: replay, suppressUntil: priorUntil)
        }
        let suppressUntil = erasedAt.addingTimeInterval(policy.eraseCooldownSeconds)
        let state = try RatingRequestAttemptLedgerStateV1(revision: 1,
            origin: .erasedCooldown(erasedAt: erasedAt, suppressUntil: suppressUntil),
            attempts: [], clockHighWatermarkUTC: erasedAt)
        let receipt = try await store.compareAndSwap(operationID: eraseOperationID,
            expectedRevision: nil, successor: state)
        try validate(receipt, expectedOperationID: eraseOperationID,
                     expectedRevision: nil, state: state)
        guard case .current(let readBack) = try await store.load(), readBack == state else {
            throw RatingEligibilityFailureV1.staleState
        }
        return .init(receipt: receipt, suppressUntil: suppressUntil)
    }

    private func evaluate(completions: [RatingEligibleCompletionProjectionV1],
                          marketingVersion: RatingMarketingVersionV1,
                          buildVersion: RatingBuildVersionV1,
                          naturalStop: RatingNaturalStopV1,
                          loaded: RatingLedgerLoadResultV1,
                          now: Date) -> RatingEligibilityProjectionV1 {
        var reasons = Set<RatingEligibilityReasonV1>()
        let distinct = Dictionary(grouping: completions, by: \.activitySeriesID).compactMap {
            $0.value.min(by: { $0.completedAt < $1.completedAt })
        }
        let dates = distinct.map(\.completedAt)
        let span: TimeInterval
        if let earliest = dates.min(), let latest = dates.max() {
            span = latest.timeIntervalSince(earliest)
        } else {
            span = 0
        }
        if distinct.count < policy.minimumDistinctSeries { reasons.insert(.insufficientDistinctSeries) }
        if span < policy.minimumSeriesSpanSeconds { reasons.insert(.insufficientSevenDaySpan) }
        if !naturalStop.isLaterVoluntaryReopen
            || !completions.contains(where: { $0.snapshotSHA256 == naturalStop.successfullyRetrievedSnapshotSHA256 }) {
            reasons.insert(.noNaturalIdleStop)
        }
        if !naturalStop.activeContexts.isEmpty { reasons.insert(.activeContext) }
        if !naturalStop.activeSceneAvailable { reasons.insert(.sceneUnavailable) }
        switch nativeRequest.availability {
        case .available: break
        case .sceneUnavailable: reasons.insert(.sceneUnavailable)
        case .disabledUnverifiedPlatform:
            reasons.insert(.automaticRequestDisabledUnverifiedPlatform)
        }
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            return projection(reasons: [.clockRollbackDetected], completions: completions)
        }
        let state: RatingRequestAttemptLedgerStateV1?
        switch loaded {
        case .absentFreshInstall: state = nil
        case .current(let value):
            guard (try? value.validate()) != nil else {
                return projection(reasons: [.ledgerCorrupt], completions: completions)
            }
            state = value
        case .corrupt: return projection(reasons: [.ledgerCorrupt], completions: completions)
        case .futureVersion: return projection(reasons: [.ledgerFutureVersion], completions: completions)
        case .migrationFailed: return projection(reasons: [.ledgerMigrationFailed], completions: completions)
        }
        let highWatermark = max(state?.clockHighWatermarkUTC ?? .distantPast,
                                dates.max() ?? .distantPast)
        if now < highWatermark || naturalStop.occurredAt > now { reasons.insert(.clockRollbackDetected) }
        if let state {
            if state.attempts.contains(where: { $0.marketingVersion == marketingVersion }) {
                reasons.insert(.alreadyAttemptedForVersion)
            }
            if let last = state.attempts.map(\.reservedAt).max(),
               now.timeIntervalSince(last) < policy.minimumAttemptIntervalSeconds {
                reasons.insert(.withinOneHundredTwentyDayCooldown)
            }
            let rolling = state.attempts.filter {
                let age = now.timeIntervalSince($0.reservedAt)
                return age >= 0 && age < policy.rollingYearSeconds
            }
            if rolling.count >= policy.maximumAttemptsPerRollingYear {
                reasons.insert(.rollingYearAttemptLimit)
            }
            if case .erasedCooldown(_, let until) = state.origin, now < until {
                reasons.insert(.erasedInstallationCooldown)
            }
        }
        return .init(eligible: reasons.isEmpty, reasons: reasons.sorted(),
                     distinctSeriesCount: distinct.count, observedSeriesSpanSeconds: max(0, span),
                     supportVisible: true, recoveryVisible: true)
    }

    private func projection(reasons: [RatingEligibilityReasonV1],
                            completions: [RatingEligibleCompletionProjectionV1])
        -> RatingEligibilityProjectionV1 {
        .init(eligible: false, reasons: Array(Set(reasons)).sorted(),
              distinctSeriesCount: Set(completions.map(\.activitySeriesID)).count,
              observedSeriesSpanSeconds: 0, supportVisible: true, recoveryVisible: true)
    }

    private func validate(_ receipt: RatingLedgerPersistenceReceiptV1,
                          expectedOperationID: UUID, expectedRevision: UInt64?,
                          state: RatingRequestAttemptLedgerStateV1) throws {
        guard receipt.operationID == expectedOperationID,
              receipt.expectedRevision == expectedRevision,
              receipt.resultingRevision == state.revision,
              receipt.stateSHA256 == state.stateSHA256 else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
    }

    private struct IdempotencyBasis: Codable {
        let eventID: UUID
        let policySHA256: String
        let marketingVersion: RatingMarketingVersionV1
        let buildVersion: RatingBuildVersionV1
    }
}

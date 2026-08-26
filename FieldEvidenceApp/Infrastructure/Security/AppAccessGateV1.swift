import Foundation

actor AppAccessGateV1: AppAccessGatePortV1 {
    private let authentication: any LocalAuthenticationClient
    private let clock: any ApplicationClock
    private let identifiers: any ApplicationIDSource
    private var state: AppAccessStateV1
    private var enabled: Bool
    private var generation: UInt64 = 0
    private var activeAttemptID: UUID?
    private var privacyCover = true

    init(
        setting: DeviceLocalAppLockSettingReadV1,
        authentication: any LocalAuthenticationClient,
        clock: any ApplicationClock,
        identifiers: any ApplicationIDSource
    ) {
        self.authentication = authentication
        self.clock = clock
        self.identifiers = identifiers
        switch setting {
        case .absentDisabled:
            enabled = false
            state = .disabled
            privacyCover = false
        case .value(let value):
            do {
                try value.validate()
                enabled = value.isEnabled
                state = value.isEnabled ? .locked(reason: .coldLaunch) : .disabled
                privacyCover = value.isEnabled
            } catch {
                enabled = true
                state = .configurationUnknownLocked
                privacyCover = true
            }
        case .corruptOrAmbiguous:
            enabled = true
            state = .configurationUnknownLocked
            privacyCover = true
        case .protectedDataUnavailable:
            enabled = true
            state = .locked(reason: .protectedDataUnavailable)
            privacyCover = true
        }
    }

    func currentState() -> AppAccessStateV1 { state }

    func privacyCoverRequired() -> Bool { privacyCover }

    func requireContentAccess() throws {
        guard state.permitsContentAccess else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    func lock(reason: AppLockReasonV1) async {
        // Lock is also the cancellation boundary for an in-flight opt-in
        // attempt. Invalidate its generation before consulting the currently
        // disabled setting so a background edge cannot strand or later revive
        // that attempt.
        let cancelled = activeAttemptID
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        if enabled {
            state = .locked(reason: reason)
            privacyCover = true
        } else {
            state = .disabled
            privacyCover = false
        }
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    func sceneBecameInactive() {
        privacyCover = enabled
    }

    func sceneBecameActive() {
        switch state {
        case .disabled, .unlockedForeground:
            privacyCover = false
        case .locked, .authenticating, .interruptedLocked,
             .configurationUnknownLocked:
            privacyCover = true
        }
    }

    func setEnabledAfterAuthenticated(_ value: Bool) async throws {
        guard case .unlockedForeground = state else {
            throw AppAccessContractFailureV1.accessDenied
        }
        enabled = value
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        state = value ? .locked(reason: .pendingRecovery) : .disabled
        privacyCover = value
    }

    func markRecoveryComplete(enabled value: Bool) throws {
        guard value == enabled else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        state = value ? .locked(reason: .coldLaunch) : .disabled
        privacyCover = value
    }

    func markConfigurationUnknown() async {
        let cancelled = activeAttemptID
        enabled = true
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        state = .configurationUnknownLocked
        privacyCover = true
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    func eraseAccessState() async {
        let cancelled = activeAttemptID
        enabled = false
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        state = .disabled
        privacyCover = false
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    func authenticate(
        trigger: LocalAuthenticationTriggerV1
    ) async -> LocalAuthenticationOutcomeV1 {
        guard permitsAuthentication(trigger), activeAttemptID == nil,
              generation < UInt64.max else {
            return .interrupted
        }
        generation += 1
        let capturedGeneration = generation
        let attemptID = identifiers.makeID()
        guard attemptID != SettingsValidationV1.zeroUUID else {
            state = .configurationUnknownLocked
            privacyCover = true
            return .unavailable
        }
        let attempt: LocalAuthenticationAttemptV1
        do {
            attempt = try LocalAuthenticationAttemptV1(
                attemptID: attemptID,
                trigger: trigger,
                requestedAt: clock.now()
            )
        } catch {
            state = .configurationUnknownLocked
            privacyCover = true
            return .unavailable
        }
        activeAttemptID = attemptID
        state = .authenticating(attemptID: attemptID)
        privacyCover = true
        let availability = await authentication.availability()
        guard isCurrentAttempt(attemptID, generation: capturedGeneration) else {
            return .interrupted
        }
        guard availability.permitsDeviceOwnerAuthentication else {
            activeAttemptID = nil
            applyUnavailable(availability.status)
            return outcome(for: availability.status)
        }
        let result = await authentication.authenticate(attempt)
        guard isCurrentAttempt(attemptID, generation: capturedGeneration) else {
            return .interrupted
        }
        activeAttemptID = nil
        switch result {
        case .authenticated:
            let sessionID = identifiers.makeID()
            guard sessionID != SettingsValidationV1.zeroUUID else {
                state = .configurationUnknownLocked
                return .unavailable
            }
            state = .unlockedForeground(sessionID: sessionID)
            privacyCover = false
        case .userCancelled, .appCancelled, .systemCancelled:
            state = .locked(reason: .authenticationCancelled)
        case .authenticationFailed:
            state = .locked(reason: .authenticationFailed)
        case .biometryLockedOut:
            state = .locked(reason: .authenticationLockedOut)
        case .biometryNotEnrolled:
            state = .locked(reason: .biometryNotEnrolled)
        case .biometryChanged:
            state = .locked(reason: .biometryChanged)
        case .devicePasscodeNotSet:
            state = .locked(reason: .devicePasscodeRemoved)
        case .unavailable:
            state = .configurationUnknownLocked
        case .interrupted:
            state = .interruptedLocked
        }
        privacyCover = !state.permitsContentAccess
        return result
    }

    private func isCurrentAttempt(_ attemptID: UUID, generation value: UInt64) -> Bool {
        guard generation == value,
              activeAttemptID == attemptID,
              case .authenticating(let currentID) = state else {
            return false
        }
        return currentID == attemptID
    }

    private func permitsAuthentication(_ trigger: LocalAuthenticationTriggerV1) -> Bool {
        switch (state, trigger) {
        case (.disabled, .enableAppLock): return true
        case (.configurationUnknownLocked, .repairConfiguration): return true
        case (.locked, .unlock), (.interruptedLocked, .unlock): return enabled
        case (.unlockedForeground, .disableAppLock): return enabled
        default: return false
        }
    }

    private func advanceGenerationOrFailClosed() {
        if generation == UInt64.max {
            state = .configurationUnknownLocked
            enabled = true
        } else {
            generation += 1
        }
    }

    private func applyUnavailable(_ value: LocalAuthenticationAvailabilityStatusV1) {
        enabled = true
        privacyCover = true
        switch value {
        case .devicePasscodeNotSet: state = .locked(reason: .devicePasscodeRemoved)
        case .biometryNotEnrolled: state = .locked(reason: .biometryNotEnrolled)
        case .biometryLockedOut: state = .locked(reason: .authenticationLockedOut)
        case .available, .unsupported, .temporarilyUnavailable:
            state = .configurationUnknownLocked
        }
    }

    private func outcome(
        for value: LocalAuthenticationAvailabilityStatusV1
    ) -> LocalAuthenticationOutcomeV1 {
        switch value {
        case .devicePasscodeNotSet: return .devicePasscodeNotSet
        case .biometryNotEnrolled: return .biometryNotEnrolled
        case .biometryLockedOut: return .biometryLockedOut
        case .available, .unsupported, .temporarilyUnavailable: return .unavailable
        }
    }
}

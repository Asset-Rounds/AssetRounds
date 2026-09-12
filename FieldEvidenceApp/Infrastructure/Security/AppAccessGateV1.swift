import Foundation

actor AppAccessGateV1: AppAccessGatePortV1 {
    fileprivate final class ContentReadOwner: Sendable {}
    fileprivate final class ConfigurationAuthenticationOwner: Sendable {}
    fileprivate final class ToggleAuthenticationOwner: Sendable {}

    /// Only successful enable/disable device-owner authentication can mint this
    /// proof. A content-read token or an ordinary unlock cannot replace it.
    struct ToggleAuthenticationToken: Sendable {
        fileprivate let owner: ToggleAuthenticationOwner
        fileprivate let generation: UInt64
        fileprivate let sessionID: UUID
        fileprivate let targetEnabled: Bool
    }

    /// A repair proof authorizes configuration completion only. It cannot be
    /// serialized or used as a content permit, including after authentication.
    struct ConfigurationAuthenticationToken: Sendable {
        fileprivate let owner: ConfigurationAuthenticationOwner
        fileprivate let generation: UInt64
        fileprivate let sessionID: UUID
    }

    /// An operation-scoped publication check, not a portable access permit.
    /// Only this file can construct one; neither it nor its owner is Codable.
    struct ContentReadToken: Sendable {
        fileprivate let owner: ContentReadOwner
        fileprivate let epoch: UInt64
        fileprivate let surface: AppAccessContentReadSurfaceV1
    }

    private let authentication: any LocalAuthenticationClient
    private let clock: any ApplicationClock
    private let identifiers: any ApplicationIDSource
    private var state: AppAccessStateV1
    private var enabled: Bool
    private var generation: UInt64 = 0
    private var activeAttemptID: UUID?
    private var privacyCover = true
    private let contentReadOwner = ContentReadOwner()
    private var contentReadEpoch: UInt64 = 0
    private var contentReadEpochExhausted = false
    private var sceneIsActive = true
    private var configurationRecoveryRequired = false
    private let configurationAuthenticationOwner = ConfigurationAuthenticationOwner()
    private var configurationAuthentication: ConfigurationAuthenticationToken?
    private let toggleAuthenticationOwner = ToggleAuthenticationOwner()
    private var toggleAuthentication: ToggleAuthenticationToken?

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
                configurationRecoveryRequired = true
                enabled = true
                state = .configurationUnknownLocked
                privacyCover = true
            }
        case .corruptOrAmbiguous:
            configurationRecoveryRequired = true
            enabled = true
            state = .configurationUnknownLocked
            privacyCover = true
        case .protectedDataUnavailable:
            configurationRecoveryRequired = true
            enabled = true
            state = .locked(reason: .protectedDataUnavailable)
            privacyCover = true
        }
    }

    func currentState() -> AppAccessStateV1 { state }

    func requiresConfigurationRecovery() -> Bool { configurationRecoveryRequired }

    func privacyCoverRequired() -> Bool { privacyCover }

    func beginContentRead(for surface: AppAccessContentReadSurfaceV1) throws -> ContentReadToken {
        try requireCurrentContentReadAccess()
        return ContentReadToken(owner: contentReadOwner, epoch: contentReadEpoch, surface: surface)
    }

    func validateContentRead(_ token: ContentReadToken,
                             for surface: AppAccessContentReadSurfaceV1) throws {
        try requireCurrentContentReadAccess()
        guard token.owner === contentReadOwner, token.epoch == contentReadEpoch,
              token.surface == surface else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    private func requireCurrentContentReadAccess() throws {
        guard !configurationRecoveryRequired,
              !contentReadEpochExhausted, state.permitsContentAccess, !privacyCover,
              !enabled || sceneIsActive else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    private func revokeContentReads() {
        toggleAuthentication = nil
        guard !contentReadEpochExhausted else { return }
        let (next, overflow) = contentReadEpoch.addingReportingOverflow(1)
        if overflow {
            // Never wrap and revive an old token, even if legacy gate state
            // subsequently returns to disabled or unlocked.
            contentReadEpochExhausted = true
        } else {
            contentReadEpoch = next
        }
    }

    func requireContentAccess() throws {
        try requireCurrentContentReadAccess()
    }

    func requireContentAccess(
        for surface: AppAccessContentReadSurfaceV1
    ) throws -> AppAccessContentPermitV1 {
        do {
            try requireCurrentContentReadAccess()
        } catch {
            throw AppAccessContentReadFailureV1.denied(surface: surface, state: state)
        }
        return try AppAccessContentPermitV1(surface: surface, state: state)
    }

    /// Concrete actor entry point for C23. State inspection and permit minting
    /// occur in this single actor turn before any OCR source can be resolved.
    func requireOCRProposalContentAccess() throws -> AppAccessContentPermitV1 {
        let permit = try requireContentAccess(for: .ocrProposal)
        try OCRProposalAppAccessBoundaryV1.validate(permit)
        return permit
    }

    /// Each C24 permit is minted from the same state snapshot in this actor
    /// turn. Neither OS capability's disposition is cached in AppAccess.
    func requireDictationProposalContentAccess() throws -> AppAccessContentPermitV1 {
        let permit = try requireContentAccess(for: .dictationProposal)
        try DictationLocationProposalAppAccessBoundaryV1.validateDictation(permit)
        return permit
    }

    func requireOneShotLocationProposalContentAccess() throws -> AppAccessContentPermitV1 {
        let permit = try requireContentAccess(for: .oneShotLocationProposal)
        try DictationLocationProposalAppAccessBoundaryV1.validateOneShotLocation(permit)
        return permit
    }

    func requireTemporalAudioCaptureAccess() throws -> AppAccessContentPermitV1 {
        let permit = try requireContentAccess(for: .temporalAudioCapture)
        try TemporalEvidenceCaptureAppAccessBoundaryV1.validateAudio(permit)
        return permit
    }

    func requireTemporalVideoCaptureAccess() throws -> AppAccessContentPermitV1 {
        let permit = try requireContentAccess(for: .temporalVideoCapture)
        try TemporalEvidenceCaptureAppAccessBoundaryV1.validateVideo(permit)
        return permit
    }

    func lock(reason: AppLockReasonV1) async {
        // Lock is also the cancellation boundary for an in-flight opt-in
        // attempt. Invalidate its generation before consulting the currently
        // disabled setting so a background edge cannot strand or later revive
        // that attempt.
        let cancelled = activeAttemptID
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        if enabled || configurationRecoveryRequired {
            state = .locked(reason: reason)
            privacyCover = true
        } else {
            state = .disabled
            privacyCover = false
        }
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    func sceneBecameInactive() {
        revokeContentReads()
        configurationAuthentication = nil
        sceneIsActive = false
        privacyCover = enabled || configurationRecoveryRequired
    }

    func sceneBecameActive() {
        revokeContentReads()
        sceneIsActive = true
        switch state {
        case .disabled, .unlockedForeground:
            privacyCover = false
        case .locked, .authenticating, .interruptedLocked,
             .configurationUnknownLocked:
            privacyCover = true
        }
    }

    func configurationAuthenticationToken() throws -> ConfigurationAuthenticationToken {
        guard let token = configurationAuthentication else {
            throw AppAccessContractFailureV1.accessDenied
        }
        try validateConfigurationAuthentication(token)
        return token
    }

    func toggleAuthenticationToken(targetEnabled: Bool) throws -> ToggleAuthenticationToken {
        guard let token = toggleAuthentication else { throw AppAccessContractFailureV1.accessDenied }
        try validateToggleAuthentication(token, targetEnabled: targetEnabled)
        return token
    }

    func validateToggleAuthentication(_ token: ToggleAuthenticationToken, targetEnabled: Bool) throws {
        guard sceneIsActive, !configurationRecoveryRequired,
              token.owner === toggleAuthenticationOwner, token.generation == generation,
              token.targetEnabled == targetEnabled,
              let current = toggleAuthentication,
              current.generation == token.generation, current.sessionID == token.sessionID,
              current.targetEnabled == token.targetEnabled,
              case .unlockedForeground(let sessionID) = state, sessionID == token.sessionID else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    func validateConfigurationAuthentication(_ token: ConfigurationAuthenticationToken) throws {
        guard configurationRecoveryRequired, sceneIsActive,
              token.owner === configurationAuthenticationOwner,
              token.generation == generation,
              let current = configurationAuthentication,
              current.sessionID == token.sessionID,
              current.generation == token.generation,
              case .configurationUnknownLocked = state else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    func setEnabledAfterAuthenticated(
        _ value: Bool, configurationToken: ConfigurationAuthenticationToken? = nil,
        toggleToken: ToggleAuthenticationToken? = nil
    ) async throws {
        guard generation < UInt64.max else { throw AppAccessContractFailureV1.staleAttempt }
        if configurationRecoveryRequired {
            guard let configurationToken, toggleToken == nil else { throw AppAccessContractFailureV1.accessDenied }
            try validateConfigurationAuthentication(configurationToken)
        } else {
            guard configurationToken == nil, let toggleToken else {
                throw AppAccessContractFailureV1.accessDenied
            }
            try validateToggleAuthentication(toggleToken, targetEnabled: value)
        }
        configurationRecoveryRequired = false
        enabled = value
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        state = value ? .locked(reason: .pendingRecovery) : .disabled
        privacyCover = value
    }

    func markRecoveryComplete(enabled value: Bool) throws {
        guard !configurationRecoveryRequired else {
            throw AppAccessContractFailureV1.accessDenied
        }
        guard value == enabled else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        revokeContentReads()
        state = value ? .locked(reason: .coldLaunch) : .disabled
        privacyCover = value
    }

    func markConfigurationUnknown() async {
        let cancelled = activeAttemptID
        configurationRecoveryRequired = true
        enabled = true
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        state = .configurationUnknownLocked
        privacyCover = true
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    func eraseAccessState() async {
        let cancelled = activeAttemptID
        configurationRecoveryRequired = false
        enabled = false
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        state = configurationRecoveryRequired ? .configurationUnknownLocked : .disabled
        privacyCover = configurationRecoveryRequired
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    func authenticate(
        trigger: LocalAuthenticationTriggerV1
    ) async -> LocalAuthenticationOutcomeV1 {
        guard permitsAuthentication(trigger), activeAttemptID == nil,
              generation < UInt64.max else {
            return .interrupted
        }
        revokeContentReads()
        configurationAuthentication = nil
        generation += 1
        let capturedGeneration = generation
        let attemptID = identifiers.makeID()
        guard attemptID != SettingsValidationV1.zeroUUID else {
            configurationRecoveryRequired = true
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
            configurationRecoveryRequired = true
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
            revokeContentReads()
            activeAttemptID = nil
            applyUnavailable(availability.status)
            return outcome(for: availability.status)
        }
        let result = await authentication.authenticate(attempt)
        guard isCurrentAttempt(attemptID, generation: capturedGeneration) else {
            return .interrupted
        }
        revokeContentReads()
        activeAttemptID = nil
        switch result {
        case .authenticated:
            let sessionID = identifiers.makeID()
            guard sessionID != SettingsValidationV1.zeroUUID else {
                configurationRecoveryRequired = true
                state = .configurationUnknownLocked
                return .unavailable
            }
            if trigger == .repairConfiguration {
                configurationAuthentication = ConfigurationAuthenticationToken(
                    owner: configurationAuthenticationOwner,
                    generation: capturedGeneration, sessionID: sessionID
                )
                state = .configurationUnknownLocked
                privacyCover = true
            } else {
                state = .unlockedForeground(sessionID: sessionID)
                privacyCover = false
                if trigger == .enableAppLock || trigger == .disableAppLock {
                    toggleAuthentication = ToggleAuthenticationToken(owner: toggleAuthenticationOwner,
                        generation: capturedGeneration, sessionID: sessionID,
                        targetEnabled: trigger == .enableAppLock)
                }
            }
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
            state = configurationRecoveryRequired ? .configurationUnknownLocked : .interruptedLocked
        case .interrupted:
            state = .interruptedLocked
        }
        privacyCover = !state.permitsContentAccess || (enabled && !sceneIsActive)
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
        if configurationRecoveryRequired { return trigger == .repairConfiguration }
        switch (state, trigger) {
        case (.disabled, .enableAppLock): return true
        case (.locked, .enableAppLock), (.interruptedLocked, .enableAppLock): return !enabled
        case (.configurationUnknownLocked, .repairConfiguration): return true
        case (.locked, .unlock), (.interruptedLocked, .unlock): return enabled
        case (.unlockedForeground, .disableAppLock): return enabled
        default: return false
        }
    }

    private func advanceGenerationOrFailClosed() {
        revokeContentReads()
        configurationAuthentication = nil
        if generation == UInt64.max {
            configurationRecoveryRequired = true
            state = .configurationUnknownLocked
            enabled = true
        } else {
            generation += 1
        }
    }

    private func applyUnavailable(_ value: LocalAuthenticationAvailabilityStatusV1) {
        privacyCover = true
        switch value {
        case .devicePasscodeNotSet: state = .locked(reason: .devicePasscodeRemoved)
        case .biometryNotEnrolled: state = .locked(reason: .biometryNotEnrolled)
        case .biometryLockedOut: state = .locked(reason: .authenticationLockedOut)
        case .available, .unsupported, .temporarilyUnavailable:
            state = configurationRecoveryRequired ? .configurationUnknownLocked : .interruptedLocked
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

extension AppAccessGateV1 {
    func permitsPrivateSystemDiscovery() -> Bool {
        !configurationRecoveryRequired && state.permitsContentAccess
    }
}

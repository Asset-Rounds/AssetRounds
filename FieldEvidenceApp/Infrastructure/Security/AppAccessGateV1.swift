import Foundation

actor AppAccessGateV1: AppAccessGatePortV1 {
    fileprivate final class ContentReadOwner: Sendable {}
    /// The publication reference is intentionally independent of actor
    /// isolation. Local content/path locks are acquired only inside its
    /// synchronous body, after this reference lock; callbacks, awaits, and
    /// reverse lock acquisition are forbidden while it is held.
    fileprivate final class ContentReadReference: @unchecked Sendable {
        private let lock = NSLock()
        private var revoked = false

        func revoke() {
            lock.lock()
            revoked = true
            lock.unlock()
        }

        func withContentRead<T>(_ body: () throws -> T) throws -> T {
            lock.lock()
            defer { lock.unlock() }
            guard !revoked else { throw AppAccessContractFailureV1.accessDenied }
            return try body()
        }
    }
    fileprivate final class ConfigurationAuthenticationOwner: Sendable {}
    fileprivate final class ToggleAuthenticationOwner: Sendable {}
    fileprivate final class ConfigurationStartupRecoveryMint: Sendable {}
    fileprivate final class EraseAdoptionOwner: Sendable {}
    fileprivate final class EraseAdoptionMint: Sendable {}
    fileprivate final class EraseConfigurationRevision: Sendable {}

    /// Destructive cleanup survives content revocation, but never a different
    /// reservation or configuration revision. Only this gate can mint it.
    struct EraseAdoptionToken: Sendable, Equatable {
        let subject: EraseAllOperationSubjectV1
        fileprivate let owner: EraseAdoptionOwner
        fileprivate let mint: EraseAdoptionMint
        fileprivate let configurationRevision: EraseConfigurationRevision
        fileprivate let originalEnabled: Bool

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.subject == rhs.subject && lhs.owner === rhs.owner
                && lhs.mint === rhs.mint
                && lhs.configurationRevision === rhs.configurationRevision
                && lhs.originalEnabled == rhs.originalEnabled
        }
    }

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

    /// A configuration-repair-only capability for the one startup recovery
    /// pipeline. It is intentionally distinct from an ordinary content read
    /// and cannot survive any content-read epoch revocation.
    struct ConfigurationStartupRecoveryToken: Sendable {
        fileprivate let owner: ConfigurationAuthenticationOwner
        fileprivate let mint: ConfigurationStartupRecoveryMint
        fileprivate let generation: UInt64
        fileprivate let sessionID: UUID
        fileprivate let operationID: UUID
        fileprivate let contentReadEpoch: UInt64
    }

    /// An operation-scoped publication check, not a portable access permit.
    /// Only this file can construct one; neither it nor its owner is Codable.
    struct ContentReadToken: Sendable {
        fileprivate let owner: ContentReadOwner
        fileprivate let epoch: UInt64
        fileprivate let surface: AppAccessContentReadSurfaceV1
        fileprivate let reference: ContentReadReference

        /// Runs only a local, synchronous protected operation. This holds the
        /// publication reference before any local path lock; the body must not
        /// await, call an actor, or invoke a callback that can re-enter here.
        func withContentRead<T>(
            for surface: AppAccessContentReadSurfaceV1,
            _ body: () throws -> T
        ) throws -> T {
            guard self.surface == surface else {
                throw AppAccessContractFailureV1.accessDenied
            }
            return try reference.withContentRead(body)
        }
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
    private var contentReadReference = ContentReadReference()
    private var contentReadEpoch: UInt64 = 0
    private var contentReadEpochExhausted = false
    private var sceneIsActive = true
    private var configurationRecoveryRequired = false
    // This is distinct from configuration uncertainty.  A runtime protected
    // data edge must revoke even a known-disabled capability, but a later
    // verified typed read can restore that capability without inventing an
    // unknown configuration repair transaction.
    private var protectedDataUnavailableHold = false
    private let configurationAuthenticationOwner = ConfigurationAuthenticationOwner()
    private var configurationAuthentication: ConfigurationAuthenticationToken?
    private var configurationStartupRecovery: ConfigurationStartupRecoveryToken?
    private let toggleAuthenticationOwner = ToggleAuthenticationOwner()
    private var toggleAuthentication: ToggleAuthenticationToken?
    private var configurationActiveSettlement: CheckedContinuation<Void, Never>?
    private let eraseAdoptionOwner = EraseAdoptionOwner()
    private var eraseConfigurationRevision = EraseConfigurationRevision()
    private var eraseAdoption: EraseAdoptionToken?
    private var postEraseStartupRequired = false

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
            protectedDataUnavailableHold = true
            enabled = true
            state = .locked(reason: .protectedDataUnavailable)
            privacyCover = true
        }
    }

    func currentState() -> AppAccessStateV1 { state }

    func requiresConfigurationRecovery() -> Bool {
        configurationRecoveryRequired || protectedDataUnavailableHold
    }

    func protectedDataAvailabilityRecoveryGeneration() -> UInt64? {
        protectedDataUnavailableHold ? generation : nil
    }

    func privacyCoverRequired() -> Bool { privacyCover }

    func beginContentRead(for surface: AppAccessContentReadSurfaceV1) throws -> ContentReadToken {
        try requireContentReadAccess(for: surface)
        return ContentReadToken(
            owner: contentReadOwner, epoch: contentReadEpoch,
            surface: surface, reference: contentReadReference
        )
    }

    func validateContentRead(_ token: ContentReadToken,
                             for surface: AppAccessContentReadSurfaceV1) throws {
        try requireContentReadAccess(for: surface)
        guard token.owner === contentReadOwner, token.epoch == contentReadEpoch,
              token.surface == surface else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    /// Immutable issuer identity only. Callers must still fence the actual
    /// synchronous read with the token's surface and revocation reference.
    nonisolated func issuedContentReadToken(_ token: ContentReadToken) -> Bool {
        token.owner === contentReadOwner
    }

    private func requireCurrentContentReadAccess() throws {
        guard eraseAdoption == nil, !postEraseStartupRequired,
              !configurationRecoveryRequired, !protectedDataUnavailableHold,
              !contentReadEpochExhausted, state.permitsContentAccess, !privacyCover,
              !enabled || sceneIsActive else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    private func requireContentReadAccess(for surface: AppAccessContentReadSurfaceV1) throws {
        if postEraseStartupRequired, surface == .startupRecovery {
            guard eraseAdoption == nil, sceneIsActive, !enabled,
                  !configurationRecoveryRequired, !protectedDataUnavailableHold,
                  !contentReadEpochExhausted else {
                throw AppAccessContractFailureV1.accessDenied
            }
            return
        }
        try requireCurrentContentReadAccess()
    }

    func reserveEraseAdoption(
        subject: EraseAllOperationSubjectV1,
        authorization: ContentReadToken
    ) throws -> EraseAdoptionToken {
        guard eraseAdoption == nil, !postEraseStartupRequired,
              activeAttemptID == nil, sceneIsActive,
              subject.eraseID != SettingsValidationV1.zeroUUID,
              subject.newGenerationID != SettingsValidationV1.zeroUUID,
              subject.eraseID != subject.newGenerationID,
              subject.applicationSupportURL.isFileURL,
              subject.applicationSupportURL == subject.applicationSupportURL.standardizedFileURL else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        // Validate the original caller's token in the same actor turn as the
        // reservation; consulting current unlocked state would permit ABA.
        try validateContentRead(authorization, for: .startupRecovery)
        let token = EraseAdoptionToken(subject: subject, owner: eraseAdoptionOwner,
            mint: EraseAdoptionMint(), configurationRevision: eraseConfigurationRevision,
            originalEnabled: enabled)
        eraseAdoption = token
        revokeContentReads()
        configurationAuthentication = nil
        state = .locked(reason: .pendingRecovery)
        privacyCover = true
        return token
    }

    func validateEraseAdoption(_ token: EraseAdoptionToken) throws {
        guard token.owner === eraseAdoptionOwner,
              token.configurationRevision === eraseConfigurationRevision,
              eraseAdoption == token else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    func requireConfigurationMutationAdmission(allowProtectedDataRecovery: Bool = false) throws {
        guard eraseAdoption == nil,
              !postEraseStartupRequired || (allowProtectedDataRecovery && protectedDataUnavailableHold) else {
            throw AppAccessContractFailureV1.invalidTransition
        }
    }

    /// Only the service's descriptor-proven rollback may release a full-Erase
    /// reservation without a completion receipt. It restores the original
    /// configuration, never the original content or authentication epoch.
    func abandonEraseAdmission(
        _ receipt: AbortedEraseAdmissionReceiptV1,
        setting: DeviceLocalAppLockSettingReadV1
    ) throws {
        let token = receipt.reservation
        try validateEraseAdoption(token)
        guard receipt.subject == token.subject,
              receipt.originalGenerationID != SettingsValidationV1.zeroUUID,
              receipt.originalGenerationID != receipt.subject.newGenerationID,
              generation < UInt64.max, !contentReadEpochExhausted else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let currentEnabled: Bool
        switch setting {
        case .absentDisabled:
            currentEnabled = false
        case .value(let value):
            try value.validate()
            currentEnabled = value.isEnabled
        case .corruptOrAmbiguous, .protectedDataUnavailable:
            throw AppAccessContractFailureV1.configurationUnknown
        }
        guard currentEnabled == token.originalEnabled else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        enabled = token.originalEnabled
        eraseConfigurationRevision = EraseConfigurationRevision()
        eraseAdoption = nil
        if protectedDataUnavailableHold {
            state = .locked(reason: .protectedDataUnavailable)
            privacyCover = true
        } else if configurationRecoveryRequired {
            state = .configurationUnknownLocked
            privacyCover = true
        } else if enabled {
            state = .locked(reason: .interrupted)
            privacyCover = true
        } else {
            state = .disabled
            privacyCover = !sceneIsActive
        }
    }

    /// The receipt proves physical completion. It does not authorize ordinary
    /// content: startup must acquire a fresh active-scene recovery token.
    func adoptCompletedErase(
        _ receipt: CompletedEraseReceiptV1,
        token: EraseAdoptionToken
    ) throws {
        try validateEraseAdoption(token)
        guard receipt.subject == token.subject, receipt.reservation == token,
              generation < UInt64.max, !contentReadEpochExhausted else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        configurationRecoveryRequired = false
        enabled = false
        eraseConfigurationRevision = EraseConfigurationRevision()
        eraseAdoption = nil
        postEraseStartupRequired = true
        state = protectedDataUnavailableHold
            ? .locked(reason: .protectedDataUnavailable) : .disabled
        privacyCover = true
    }

    /// Called only after the existing router has completed its recovery under
    /// this original token. Ordinary startup is a validated no-op here.
    func completePostEraseStartup(_ token: ContentReadToken) throws {
        try validateContentRead(token, for: .startupRecovery)
        guard postEraseStartupRequired else { return }
        guard sceneIsActive, eraseAdoption == nil, !protectedDataUnavailableHold,
              !configurationRecoveryRequired, !enabled else {
            throw AppAccessContractFailureV1.accessDenied
        }
        postEraseStartupRequired = false
        state = .disabled
        privacyCover = false
    }

    private func revokeContentReads() {
        toggleAuthentication = nil
        configurationStartupRecovery = nil
        // Invalidate the old reference before the calling transition can
        // publish a changed access state. A concurrent local publication
        // therefore either completes under its old authorization or observes
        // denial; it cannot begin after revocation.
        contentReadReference.revoke()
        guard !contentReadEpochExhausted else { return }
        let (next, overflow) = contentReadEpoch.addingReportingOverflow(1)
        if overflow {
            // Never wrap and revive an old token, even if legacy gate state
            // subsequently returns to disabled or unlocked.
            contentReadEpochExhausted = true
        } else {
            contentReadEpoch = next
            contentReadReference = ContentReadReference()
        }
    }

    func requireContentAccess() throws {
        try requireCurrentContentReadAccess()
    }

    func requireContentAccess(
        for surface: AppAccessContentReadSurfaceV1
    ) async throws -> AppAccessContentPermitV1 {
        try currentContentPermit(for: surface)
    }

    private func currentContentPermit(
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
        let permit = try currentContentPermit(for: .ocrProposal)
        try OCRProposalAppAccessBoundaryV1.validate(permit)
        return permit
    }

    /// Each C24 permit is minted from the same state snapshot in this actor
    /// turn. Neither OS capability's disposition is cached in AppAccess.
    func requireDictationProposalContentAccess() throws -> AppAccessContentPermitV1 {
        let permit = try currentContentPermit(for: .dictationProposal)
        try DictationLocationProposalAppAccessBoundaryV1.validateDictation(permit)
        return permit
    }

    func requireOneShotLocationProposalContentAccess() throws -> AppAccessContentPermitV1 {
        let permit = try currentContentPermit(for: .oneShotLocationProposal)
        try DictationLocationProposalAppAccessBoundaryV1.validateOneShotLocation(permit)
        return permit
    }

    func requireTemporalAudioCaptureAccess() throws -> AppAccessContentPermitV1 {
        let permit = try currentContentPermit(for: .temporalAudioCapture)
        try TemporalEvidenceCaptureAppAccessBoundaryV1.validateAudio(permit)
        return permit
    }

    func requireTemporalVideoCaptureAccess() throws -> AppAccessContentPermitV1 {
        let permit = try currentContentPermit(for: .temporalVideoCapture)
        try TemporalEvidenceCaptureAppAccessBoundaryV1.validateVideo(permit)
        return permit
    }

    func lock(reason: AppLockReasonV1) async {
        // Lock is also the cancellation boundary for an in-flight opt-in
        // attempt. Invalidate its generation before consulting the currently
        // disabled setting so a background edge cannot strand or later revive
        // that attempt.
        let cancelled = activeAttemptID
        if eraseAdoption != nil || postEraseStartupRequired {
            if reason == .returnedFromBackground || reason == .interrupted {
                // Cleanup can finish without an earlier sceneInactive edge.
                // A background/termination callback cannot leave its fresh
                // post-Erase startup capability marked foreground-active.
                sceneIsActive = false
            }
        }
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        if protectedDataUnavailableHold {
            state = .locked(reason: .protectedDataUnavailable)
            privacyCover = true
        } else if enabled || configurationRecoveryRequired || eraseAdoption != nil {
            state = .locked(reason: reason)
            privacyCover = true
        } else {
            state = .disabled
            privacyCover = postEraseStartupRequired
        }
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    /// A protected-data lifecycle edge is stronger than an ordinary lock:
    /// disabled configuration must be covered too, and no prior unlock or
    /// toggle proof may survive until the coordinator observes a fresh typed
    /// configuration read.
    func markProtectedDataUnavailable() async {
        let cancelled = activeAttemptID
        protectedDataUnavailableHold = true
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        state = .locked(reason: .protectedDataUnavailable)
        privacyCover = true
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    /// Releases only the runtime availability hold.  The coordinator supplies
    /// the independently checked local configuration result, so a Boolean
    /// alone can never make content readable again.
    func recoverProtectedDataAvailability(
        setting: DeviceLocalAppLockSettingReadV1,
        configurationVerified: Bool,
        expectedGeneration: UInt64
    ) throws {
        guard eraseAdoption == nil, protectedDataUnavailableHold,
              generation == expectedGeneration else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let recoveredEnabled: Bool
        switch setting {
        case .absentDisabled:
            recoveredEnabled = false
        case .value(let value):
            try value.validate()
            recoveredEnabled = value.isEnabled
        case .corruptOrAmbiguous, .protectedDataUnavailable:
            throw AppAccessContractFailureV1.configurationUnknown
        }
        protectedDataUnavailableHold = false
        revokeContentReads()
        guard configurationVerified,
              !configurationRecoveryRequired,
              recoveredEnabled == enabled else {
            configurationRecoveryRequired = true
            enabled = true
            state = .configurationUnknownLocked
            privacyCover = true
            return
        }
        state = recoveredEnabled ? .locked(reason: .coldLaunch) : .disabled
        privacyCover = recoveredEnabled || postEraseStartupRequired
    }

    func sceneBecameInactive() {
        revokeContentReads()
        configurationAuthentication = nil
        sceneIsActive = false
        privacyCover = enabled || configurationRecoveryRequired
            || protectedDataUnavailableHold || activeAttemptID != nil
            || eraseAdoption != nil || postEraseStartupRequired
    }

    func sceneBecameActive() {
        revokeContentReads()
        sceneIsActive = true
        switch state {
        case .disabled, .unlockedForeground:
            privacyCover = eraseAdoption != nil || postEraseStartupRequired
        case .locked, .authenticating, .interruptedLocked,
             .configurationUnknownLocked:
            privacyCover = true
        }
        resumeConfigurationActiveSettlement()
    }

    func configurationAuthenticationToken() throws -> ConfigurationAuthenticationToken {
        guard let token = configurationAuthentication else {
            throw AppAccessContractFailureV1.accessDenied
        }
        try validateConfigurationAuthentication(token)
        return token
    }

    func beginConfigurationStartupRecovery(
        _ configuration: ConfigurationAuthenticationToken,
        operationID: UUID
    ) throws -> ConfigurationStartupRecoveryToken {
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        try validateConfigurationAuthentication(configuration)
        let token = ConfigurationStartupRecoveryToken(
            owner: configurationAuthenticationOwner,
            mint: ConfigurationStartupRecoveryMint(),
            generation: configuration.generation,
            sessionID: configuration.sessionID,
            operationID: operationID,
            contentReadEpoch: contentReadEpoch
        )
        configurationStartupRecovery = token
        return token
    }

    func validateConfigurationStartupRecovery(
        _ token: ConfigurationStartupRecoveryToken,
        configuration: ConfigurationAuthenticationToken,
        operationID: UUID
    ) throws {
        guard operationID != SettingsValidationV1.zeroUUID,
              token.owner === configurationAuthenticationOwner,
              token.generation == configuration.generation,
              token.sessionID == configuration.sessionID,
              token.operationID == operationID,
              token.contentReadEpoch == contentReadEpoch,
              !contentReadEpochExhausted,
              let current = configurationStartupRecovery,
              current.owner === token.owner,
              current.mint === token.mint,
              current.generation == token.generation,
              current.sessionID == token.sessionID,
              current.operationID == token.operationID,
              current.contentReadEpoch == token.contentReadEpoch else {
            throw AppAccessContractFailureV1.accessDenied
        }
        try validateConfigurationAuthentication(configuration)
    }

    func toggleAuthenticationToken(targetEnabled: Bool) throws -> ToggleAuthenticationToken {
        guard let token = toggleAuthentication else { throw AppAccessContractFailureV1.accessDenied }
        try validateToggleAuthentication(token, targetEnabled: targetEnabled)
        return token
    }

    func validateToggleAuthentication(_ token: ToggleAuthenticationToken, targetEnabled: Bool) throws {
        guard eraseAdoption == nil, !postEraseStartupRequired,
              sceneIsActive, !configurationRecoveryRequired, !protectedDataUnavailableHold,
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
        guard eraseAdoption == nil, !postEraseStartupRequired,
              configurationRecoveryRequired, sceneIsActive,
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
        guard eraseAdoption == nil, !postEraseStartupRequired,
              generation < UInt64.max, !protectedDataUnavailableHold else {
            throw AppAccessContractFailureV1.staleAttempt
        }
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
        eraseConfigurationRevision = EraseConfigurationRevision()
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        state = value ? .locked(reason: .pendingRecovery) : .disabled
        privacyCover = value
    }

    func markRecoveryComplete(enabled value: Bool) throws {
        guard eraseAdoption == nil, !postEraseStartupRequired,
              activeAttemptID == nil, !configurationRecoveryRequired,
              !protectedDataUnavailableHold else {
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
        state = protectedDataUnavailableHold
            ? .locked(reason: .protectedDataUnavailable) : .configurationUnknownLocked
        privacyCover = true
        if let cancelled { await authentication.cancel(attemptID: cancelled) }
    }

    func eraseAccessState() async {
        // Legacy configuration-only erase cannot reset a live full-erase
        // reservation or bypass its post-completion startup barrier.
        guard eraseAdoption == nil, !postEraseStartupRequired else { return }
        let cancelled = activeAttemptID
        configurationRecoveryRequired = false
        enabled = false
        eraseConfigurationRevision = EraseConfigurationRevision()
        advanceGenerationOrFailClosed()
        activeAttemptID = nil
        if protectedDataUnavailableHold {
            state = .locked(reason: .protectedDataUnavailable)
            privacyCover = true
        } else {
            state = configurationRecoveryRequired ? .configurationUnknownLocked : .disabled
            privacyCover = configurationRecoveryRequired
        }
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
        if result == .authenticated, trigger != .unlock {
            while isCurrentAttempt(attemptID, generation: capturedGeneration),
                  !sceneIsActive, !Task.isCancelled {
                await waitForConfigurationActiveScene(
                    attemptID: attemptID, generation: capturedGeneration
                )
            }
            guard isCurrentAttempt(attemptID, generation: capturedGeneration), !Task.isCancelled else {
                if Task.isCancelled {
                    await cancelConfigurationAuthentication(attemptID: attemptID, generation: capturedGeneration)
                }
                return .interrupted
            }
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

    /// A system-authentication callback can precede the active scene edge.
    /// Keep that original attempt covered until active, then mint its proof.
    /// Ordinary unlock intentionally retains its covered inactive completion.
    private func waitForConfigurationActiveScene(
        attemptID: UUID, generation value: UInt64
    ) async {
        await withTaskCancellationHandler {
            guard isCurrentAttempt(attemptID, generation: value), !sceneIsActive,
                  !Task.isCancelled else { return }
            await withCheckedContinuation { configurationActiveSettlement = $0 }
        } onCancel: {
            Task { await self.cancelConfigurationAuthentication(attemptID: attemptID, generation: value) }
        }
    }

    private func cancelConfigurationAuthentication(attemptID: UUID, generation value: UInt64) async {
        guard isCurrentAttempt(attemptID, generation: value) else { return }
        await lock(reason: .interrupted)
    }

    private func resumeConfigurationActiveSettlement() {
        let settlement = configurationActiveSettlement
        configurationActiveSettlement = nil
        settlement?.resume()
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
        guard eraseAdoption == nil, !postEraseStartupRequired,
              !protectedDataUnavailableHold else { return false }
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
        resumeConfigurationActiveSettlement()
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
        do { try requireCurrentContentReadAccess(); return true }
        catch { return false }
    }
}

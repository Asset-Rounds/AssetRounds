import Foundation

/// Production notification state machine over injected durable and system
/// effects. The effect owns descriptor-pinned persistence and OS scheduling;
/// this actor enforces one mutation, exact journal phases, and readback.
actor AppLockNotificationPrivacyCoordinatorV1: AppLockNotificationPrivacyPortV1 {
    private let effects: any AppLockNotificationEffectPortV1
    private var mutationInProgress = false

    init(effects: any AppLockNotificationEffectPortV1) {
        self.effects = effects
    }

    func loadJournal() async throws -> AppLockNotificationJournalV1? {
        let journal = try await effects.loadJournalEffect()
        try journal?.priorPolicy.validate()
        try journal?.projections.forEach { try $0.validate() }
        return journal
    }

    func prepareEnable(operationID: UUID) async throws -> AppLockNotificationJournalV1 {
        try claim()
        defer { mutationInProgress = false }
        let existing = try await loadJournal()
        let result = try await effects.prepareEnableEffect(operationID: operationID)
        guard result.operationID == operationID, result.targetEnabled,
              result.disposition == .enablingPrepared
                || result.disposition == .genericProjectionApplied
                || result.disposition == .genericProjectionAdopted else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        if let existing {
            guard Self.sameSubject(existing, result),
                  existing.disposition == result.disposition else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        guard try await loadJournal() == result else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return result
    }

    func applyGenericProjection(
        _ journal: AppLockNotificationJournalV1
    ) async throws -> AppLockNotificationPrivacyDispositionV1 {
        try claim()
        defer { mutationInProgress = false }
        guard journal.targetEnabled else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        if let current = try await loadJournal(),
           Self.sameSubject(current, journal),
           current.disposition == .genericProjectionApplied
            || current.disposition == .genericProjectionAdopted {
            return .genericProjectionAdopted
        }
        let result = try await effects.publishGenericEffect(expected: journal)
        guard result.operationID == journal.operationID, result.targetEnabled,
              result.priorPolicy == journal.priorPolicy,
              result.projections == journal.projections,
              result.disposition == .genericProjectionApplied
                || result.disposition == .genericProjectionAdopted,
              try await loadJournal() == result else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return result.disposition
    }

    func prepareDisable(operationID: UUID) async throws -> AppLockNotificationJournalV1 {
        try claim()
        defer { mutationInProgress = false }
        let existing = try await loadJournal()
        let result = try await effects.prepareDisableEffect(operationID: operationID)
        guard result.operationID == operationID, !result.targetEnabled,
              result.disposition == .disablingPrepared
                || result.disposition == .priorPolicyRebuilt else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        if let existing {
            guard Self.sameSubject(existing, result),
                  existing.disposition == result.disposition else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        guard try await loadJournal() == result else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return result
    }

    func rebuildPriorPolicy(
        _ journal: AppLockNotificationJournalV1
    ) async throws -> AppLockNotificationPrivacyDispositionV1 {
        try claim()
        defer { mutationInProgress = false }
        guard !journal.targetEnabled else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        if let current = try await loadJournal(),
           Self.sameSubject(current, journal),
           current.disposition == .priorPolicyRebuilt {
            return .priorPolicyRebuilt
        }
        let result = try await effects.rebuildPriorPolicyEffect(expected: journal)
        guard result.operationID == journal.operationID, !result.targetEnabled,
              result.priorPolicy == journal.priorPolicy,
              result.projections == journal.projections,
              result.disposition == .priorPolicyRebuilt,
              try await loadJournal() == result else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return .priorPolicyRebuilt
    }

    func resolveOpaqueTokenAfterAuthentication(
        _ token: String,
        now: Date
    ) async throws -> String? {
        try await effects.resolveOpaqueTokenEffect(token, now: now)
    }

    func eraseNotificationsAndMappings(operationID: UUID) async throws {
        try claim()
        defer { mutationInProgress = false }
        try await effects.eraseNotificationsAndMappingsEffect(operationID: operationID)
        guard try await loadJournal() == nil else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    private func claim() throws {
        guard !mutationInProgress else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        mutationInProgress = true
    }

    private static func sameSubject(
        _ lhs: AppLockNotificationJournalV1,
        _ rhs: AppLockNotificationJournalV1
    ) -> Bool {
        lhs.operationID == rhs.operationID
            && lhs.targetEnabled == rhs.targetEnabled
            && lhs.priorPolicy == rhs.priorPolicy
            && lhs.projections == rhs.projections
    }
}

actor DeviceLocalAppLockSettingAdapterV1: DeviceLocalAppLockSettingPortV1 {
    private let preferences: any DevicePreferencesPortV1
    private let descriptor: SettingDescriptorV1

    init(
        preferences: any DevicePreferencesPortV1,
        registry: any SettingsRegistryPortV1
    ) throws {
        let descriptor = try registry.descriptor(for: DeviceLocalAppLockSettingV1.key)
        guard descriptor.scope == .deviceLocal,
              descriptor.valueKind == .boolean,
              descriptor.backup == .excludedDeviceLocal,
              descriptor.erase == .restoreDefault else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        self.preferences = preferences
        self.descriptor = descriptor
    }

    func readAppLockSetting() async -> DeviceLocalAppLockSettingReadV1 {
        do {
            let data = try preferences.readCanonicalValue(for: descriptor)
            let enabled = try CompatibilityCanonicalV1.decode(Bool.self, from: data)
            let value = DeviceLocalAppLockSettingV1(isEnabled: enabled)
            try value.validate()
            return .value(value)
        } catch {
            return .corruptOrAmbiguous
        }
    }

    func writeAppLockSetting(
        _ value: DeviceLocalAppLockSettingV1,
        operationID: UUID
    ) async throws -> DeviceLocalAppLockSettingWriteReceiptV1 {
        try value.validate()
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        let bytes = try CompatibilityCanonicalV1.encode(value.isEnabled)
        let before = try preferences.readCanonicalValue(for: descriptor)
        try preferences.writeCanonicalValue(
            bytes,
            descriptor: descriptor,
            operationID: operationID
        )
        let after = try preferences.readCanonicalValue(for: descriptor)
        guard after == bytes else { throw AppAccessContractFailureV1.effectMismatch }
        return DeviceLocalAppLockSettingWriteReceiptV1(
            operationID: operationID,
            value: value,
            adoptedExistingEffect: before == bytes
        )
    }

    func eraseAppLockSetting(operationID: UUID) async throws {
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        try preferences.erase(descriptors: [descriptor], operationID: operationID)
        let value = try preferences.readCanonicalValue(for: descriptor)
        guard value == descriptor.defaultCanonicalValue else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }
}

actor AppLockLifecycleCoordinatorV1 {
    static let shippingAdoption: AppLockShippingAdoptionV1 =
        .deferredUntilAcceptedS10_6Composition

    private let gate: AppAccessGateV1
    private let setting: any DeviceLocalAppLockSettingPortV1
    private let ingress: ProtectedIngressCoordinatorV1
    private let notifications: any AppLockNotificationPrivacyPortV1
    private let identifiers: any ApplicationIDSource
    private var activeOperationID: UUID?

    private init(
        gate: AppAccessGateV1,
        setting: any DeviceLocalAppLockSettingPortV1,
        ingress: ProtectedIngressCoordinatorV1,
        notifications: any AppLockNotificationPrivacyPortV1,
        identifiers: any ApplicationIDSource
    ) {
        self.gate = gate
        self.setting = setting
        self.ingress = ingress
        self.notifications = notifications
        self.identifiers = identifiers
    }

    /// Bootstraps only declarations and injected authorities. It performs no
    /// shipping scene/UI composition and reads no canonical customer content.
    static func bootstrap(
        setting: any DeviceLocalAppLockSettingPortV1,
        authentication: any LocalAuthenticationClient,
        ingressStore: any ProtectedIngressStoreV1,
        notifications: any AppLockNotificationPrivacyPortV1,
        clock: any ApplicationClock,
        identifiers: any ApplicationIDSource
    ) async throws -> AppLockLifecycleCoordinatorV1 {
        // Bootstrap ordering is security-sensitive: read only the typed
        // device-local setting, perform bounded metadata-only staging hygiene,
        // then construct the access gate. No customer payload is opened.
        let settingRead = await setting.readAppLockSetting()
        let hygieneOperationID = identifiers.makeID()
        guard hygieneOperationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        let hygiene = try await ingressStore.performBlindStartupHygiene(
            now: clock.now(),
            operationID: hygieneOperationID
        )
        let gate = AppAccessGateV1(
            setting: settingRead,
            authentication: authentication,
            clock: clock,
            identifiers: identifiers
        )
        let ingress = ProtectedIngressCoordinatorV1(
            gate: gate,
            store: ingressStore,
            clock: clock
        )
        let coordinator = AppLockLifecycleCoordinatorV1(
            gate: gate,
            setting: setting,
            ingress: ingress,
            notifications: notifications,
            identifiers: identifiers
        )
        if try await notifications.loadJournal() != nil {
            await gate.markConfigurationUnknown()
        }
        if hygiene.requiresAuthenticatedRecovery {
            await gate.markConfigurationUnknown()
        }
        return coordinator
    }

    func accessGate() -> AppAccessGateV1 { gate }

    func protectedIngress() -> ProtectedIngressCoordinatorV1 { ingress }

    func resolveNotificationTokenAfterAuthentication(
        _ token: String,
        now: Date
    ) async throws -> String? {
        let sessionID = try await unlockedSessionID()
        guard CompatibilityCanonicalV1.validSHA256(token),
              now.timeIntervalSinceReferenceDate.isFinite else {
            throw AppAccessContractFailureV1.invalidValue
        }
        let result = try await notifications.resolveOpaqueTokenAfterAuthentication(
            token,
            now: now
        )
        try await requireSameUnlockedSession(sessionID)
        return result
    }

    func enable(operationID: UUID) async throws -> AppLockConfigurationReceiptV1 {
        try validate(operationID)
        try beginOperation(operationID)
        try claim(operationID, confirmingExisting: true)
        defer { release(operationID); endOperation(operationID) }
        let outcome = await gate.authenticate(trigger: .enableAppLock)
        guard outcome == .authenticated else {
            throw AppAccessContractFailureV1.accessDenied
        }
        let sessionID = try await unlockedSessionID()
        do {
            let journal = try await notifications.prepareEnable(operationID: operationID)
            try await requireSameUnlockedSession(sessionID)
            guard journal.operationID == operationID, journal.targetEnabled,
                  journal.disposition == .enablingPrepared
                    || journal.disposition == .genericProjectionApplied
                    || journal.disposition == .genericProjectionAdopted else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let notification = try await notifications.applyGenericProjection(journal)
            try await requireSameUnlockedSession(sessionID)
            guard notification == .genericProjectionApplied
                    || notification == .genericProjectionAdopted else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let write = try await setting.writeAppLockSetting(
                DeviceLocalAppLockSettingV1(isEnabled: true),
                operationID: operationID
            )
            try await requireSameUnlockedSession(sessionID)
            guard write.operationID == operationID, write.value.isEnabled else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try await gate.setEnabledAfterAuthenticated(true)
            try await gate.markRecoveryComplete(enabled: true)
            return try AppLockConfigurationReceiptV1(
                operationID: operationID,
                enabled: true,
                authenticationOutcome: outcome,
                notificationDisposition: notification,
                settingAdoptedExistingEffect: write.adoptedExistingEffect
            )
        } catch {
            await gate.markConfigurationUnknown()
            throw error
        }
    }

    func disable(operationID: UUID) async throws -> AppLockConfigurationReceiptV1 {
        try validate(operationID)
        try beginOperation(operationID)
        try claim(operationID, confirmingExisting: true)
        defer { release(operationID); endOperation(operationID) }
        let outcome = await gate.authenticate(trigger: .disableAppLock)
        guard outcome == .authenticated else {
            throw AppAccessContractFailureV1.accessDenied
        }
        let sessionID = try await unlockedSessionID()
        do {
            let journal = try await notifications.prepareDisable(operationID: operationID)
            try await requireSameUnlockedSession(sessionID)
            guard journal.operationID == operationID, !journal.targetEnabled,
                  journal.disposition == .disablingPrepared
                    || journal.disposition == .priorPolicyRebuilt else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let write = try await setting.writeAppLockSetting(
                DeviceLocalAppLockSettingV1(isEnabled: false),
                operationID: operationID
            )
            try await requireSameUnlockedSession(sessionID)
            guard write.operationID == operationID, !write.value.isEnabled else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            // Persist the disabled setting before detailed notification state
            // can be restored. A rebuild failure therefore cannot expose
            // details while the durable lock setting is still enabled.
            let notification = try await notifications.rebuildPriorPolicy(journal)
            try await requireSameUnlockedSession(sessionID)
            guard notification == .priorPolicyRebuilt else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try await gate.setEnabledAfterAuthenticated(false)
            return try AppLockConfigurationReceiptV1(
                operationID: operationID,
                enabled: false,
                authenticationOutcome: outcome,
                notificationDisposition: notification,
                settingAdoptedExistingEffect: write.adoptedExistingEffect
            )
        } catch {
            await gate.markConfigurationUnknown()
            throw error
        }
    }

    func recoverAfterAuthentication() async throws -> AppLockRecoveryDispositionV1 {
        let recoveryOperationID = identifiers.makeID()
        try validate(recoveryOperationID)
        try beginOperation(recoveryOperationID)
        try claim(recoveryOperationID, confirmingExisting: true)
        defer { release(recoveryOperationID); endOperation(recoveryOperationID) }
        guard let journal = try await notifications.loadJournal() else {
            return .noRecoveryRequired
        }
        let outcome = await gate.authenticate(trigger: .repairConfiguration)
        guard outcome == .authenticated else {
            return .ambiguousStateLocked
        }
        let sessionID = try await unlockedSessionID()
        do {
            let notification: AppLockNotificationPrivacyDispositionV1
            if journal.targetEnabled {
                notification = try await notifications.applyGenericProjection(journal)
                try await requireSameUnlockedSession(sessionID)
                guard notification == .genericProjectionApplied
                        || notification == .genericProjectionAdopted else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
            } else {
                let write = try await setting.writeAppLockSetting(
                    DeviceLocalAppLockSettingV1(isEnabled: false),
                    operationID: journal.operationID
                )
                try await requireSameUnlockedSession(sessionID)
                guard !write.value.isEnabled else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                notification = try await notifications.rebuildPriorPolicy(journal)
                try await requireSameUnlockedSession(sessionID)
                guard notification == .priorPolicyRebuilt else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                try await gate.setEnabledAfterAuthenticated(false)
                return write.adoptedExistingEffect
                    ? .adoptedCompletedEffect : .resumedToLocked
            }
            let write = try await setting.writeAppLockSetting(
                DeviceLocalAppLockSettingV1(isEnabled: journal.targetEnabled),
                operationID: journal.operationID
            )
            try await requireSameUnlockedSession(sessionID)
            guard write.value.isEnabled == journal.targetEnabled else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try await gate.setEnabledAfterAuthenticated(journal.targetEnabled)
            if journal.targetEnabled {
                try await gate.markRecoveryComplete(enabled: true)
            }
            return write.adoptedExistingEffect
                ? .adoptedCompletedEffect : .resumedToLocked
        } catch {
            await gate.markConfigurationUnknown()
            throw error
        }
    }

    @discardableResult
    func handle(_ event: AppLockLifecycleEventV1) async throws
        -> AppLockLifecycleReceiptV1 {
        let operationID = identifiers.makeID()
        try validate(operationID)
        switch event {
        case .coldLaunch:
            await gate.lock(reason: .coldLaunch)
        case .sceneInactive:
            await gate.sceneBecameInactive()
        case .sceneBackground:
            await gate.lock(reason: .returnedFromBackground)
        case .sceneActive:
            await gate.sceneBecameActive()
        case .protectedDataUnavailable:
            await gate.lock(reason: .protectedDataUnavailable)
        case .lockNow:
            await gate.lock(reason: .lockNow)
        case .termination:
            await gate.lock(reason: .interrupted)
        case .erase:
            // Erase mutates configuration and durable effects, so it owns the
            // configuration-operation claim. Other lifecycle events are
            // deliberately preemptive: they must invalidate an in-flight
            // authenticated session so its next readback fence fails.
            try await erase(operationID: operationID)
        }
        let state = await gate.currentState()
        return try AppLockLifecycleReceiptV1(
            operationID: operationID,
            event: event,
            resultingState: Self.name(state),
            privacyCoverRequired: await gate.privacyCoverRequired(),
            contentWasRead: false
        )
    }

    func erase(operationID: UUID) async throws {
        try validate(operationID)
        try beginOperation(operationID)
        try claim(operationID, confirmingExisting: true)
        defer { release(operationID); endOperation(operationID) }
        try await performErase(operationID: operationID)
    }

    private func performErase(operationID: UUID) async throws {
        await gate.lock(reason: .interrupted)
        do {
            try await notifications.eraseNotificationsAndMappings(operationID: operationID)
            try await requireNoContentAccess()
            try await ingress.erase(operationID: operationID)
            try await requireNoContentAccess()
            try await setting.eraseAppLockSetting(operationID: operationID)
            try await requireNoContentAccess()
            await gate.eraseAccessState()
            guard await gate.currentState() == .disabled,
                  try await notifications.loadJournal() == nil else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        } catch {
            await gate.markConfigurationUnknown()
            throw error
        }
    }

    private func validate(_ operationID: UUID) throws {
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    private func beginOperation(_ operationID: UUID) throws {
        try claim(operationID)
    }

    private func claim(_ operationID: UUID) throws {
        guard activeOperationID == nil else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        activeOperationID = operationID
    }

    private func claim(_ operationID: UUID, confirmingExisting: Bool) throws {
        guard confirmingExisting, activeOperationID == operationID else {
            throw AppAccessContractFailureV1.invalidTransition
        }
    }

    private func release(_ operationID: UUID) {
        endOperation(operationID)
    }

    private func endOperation(_ operationID: UUID) {
        if activeOperationID == operationID { activeOperationID = nil }
    }

    private func unlockedSessionID() async throws -> UUID {
        guard case .unlockedForeground(let sessionID) = await gate.currentState() else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        return sessionID
    }

    private func requireSameUnlockedSession(_ expected: UUID) async throws {
        guard case .unlockedForeground(let observed) = await gate.currentState(),
              observed == expected else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    private func requireNoContentAccess() async throws {
        guard !(await gate.currentState()).permitsContentAccess else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    private static func name(_ state: AppAccessStateV1) -> String {
        switch state {
        case .disabled: return "DISABLED"
        case .locked: return "LOCKED"
        case .authenticating: return "AUTHENTICATING"
        case .unlockedForeground: return "UNLOCKED_FOREGROUND"
        case .interruptedLocked: return "INTERRUPTED_LOCKED"
        case .configurationUnknownLocked: return "CONFIGURATION_UNKNOWN_LOCKED"
        }
    }
}

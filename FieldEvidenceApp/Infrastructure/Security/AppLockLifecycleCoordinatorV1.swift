import Foundation
import UIKit

/// Production notification state machine over injected durable and system
/// effects. The effect owns descriptor-pinned persistence and OS scheduling;
/// this actor enforces one mutation, exact journal phases, and readback.
actor AppLockNotificationPrivacyCoordinatorV1: AppLockNotificationPrivacyPortV1 {
    private let effects: any AppLockNotificationEffectPortV1
    private var mutationInProgress = false

    init(effects: any AppLockNotificationEffectPortV1) {
        self.effects = effects
    }

    func bindNotificationGate(_ gate: AppAccessGateV1) async throws {
        try await effects.bindNotificationGateEffect(gate)
    }

    func loadAuthenticationSubject() async throws -> NotificationOperationSubjectV1? {
        try await effects.loadAuthenticationSubjectEffect()
    }

    func validatesLocalConfiguration(_ setting: DeviceLocalAppLockSettingReadV1) async throws -> Bool {
        try await effects.validatesLocalConfigurationEffect(setting)
    }

    func loadJournal() async throws -> AppLockNotificationJournalV1? {
        let journal = try await effects.loadJournalEffect()
        try journal?.priorPolicy.validate()
        try journal?.projections.forEach { try $0.validate() }
        return journal
    }

    func prepareEnable(operationID: UUID, authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        try await authorization.validateMutation(operationID: operationID, targetEnabled: true)
        try claim()
        defer { mutationInProgress = false }
        let existing = try await loadJournal()
        if let existing {
            if existing.operationID == operationID {
                guard existing.targetEnabled,
                      existing.disposition == .enablingPrepared
                        || existing.disposition == .genericProjectionApplied
                        || existing.disposition == .genericProjectionAdopted else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
            }
            guard existing.operationID == operationID || (!existing.targetEnabled &&
                  existing.disposition == .priorPolicyRebuilt) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        let result = try await effects.prepareEnableEffect(
            operationID: operationID, expectedPredecessor: existing, authorization: authorization
        )
        guard result.operationID == operationID, result.targetEnabled,
              result.disposition == .enablingPrepared
                || result.disposition == .genericProjectionApplied
                || result.disposition == .genericProjectionAdopted else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        guard try await loadJournal() == result else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try await authorization.validateMutation(operationID: operationID, targetEnabled: true)
        return result
    }

    func applyGenericProjection(
        _ journal: AppLockNotificationJournalV1, authorization: NotificationOperationAuthorizationV1
    ) async throws -> AppLockNotificationPrivacyDispositionV1 {
        try claim()
        defer { mutationInProgress = false }
        try await authorization.validateMutation(operationID: journal.operationID, targetEnabled: true)
        guard journal.targetEnabled else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        guard let current = try await loadJournal(), Self.sameSubject(current, journal) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let result = try await effects.publishGenericEffect(expected: current, authorization: authorization)
        guard result.operationID == journal.operationID, result.targetEnabled,
              result.priorPolicy == journal.priorPolicy,
              result.projections == journal.projections,
              result.disposition == .genericProjectionApplied
                || result.disposition == .genericProjectionAdopted,
              try await loadJournal() == result else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try await authorization.validateMutation(operationID: journal.operationID, targetEnabled: true)
        return result.disposition
    }

    func prepareDisable(operationID: UUID, authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        try await authorization.validateMutation(operationID: operationID, targetEnabled: false)
        try claim()
        defer { mutationInProgress = false }
        let existing = try await loadJournal()
        if let existing {
            if existing.operationID == operationID {
                guard !existing.targetEnabled,
                      existing.disposition == .disablingPrepared
                        || existing.disposition == .priorPolicyRebuilt else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
            }
            guard existing.operationID == operationID || (existing.targetEnabled &&
                  (existing.disposition == .genericProjectionApplied
                    || existing.disposition == .genericProjectionAdopted)) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        let result = try await effects.prepareDisableEffect(
            operationID: operationID, expectedPredecessor: existing, authorization: authorization
        )
        guard result.operationID == operationID, !result.targetEnabled,
              result.disposition == .disablingPrepared
                || result.disposition == .priorPolicyRebuilt else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        if let existing {
            guard existing.priorPolicy == result.priorPolicy else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        guard try await loadJournal() == result else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try await authorization.validateMutation(operationID: operationID, targetEnabled: false)
        return result
    }

    func rebuildPriorPolicy(
        _ journal: AppLockNotificationJournalV1, authorization: NotificationOperationAuthorizationV1
    ) async throws -> AppLockNotificationPrivacyDispositionV1 {
        try claim()
        defer { mutationInProgress = false }
        try await authorization.validateMutation(operationID: journal.operationID, targetEnabled: false)
        guard !journal.targetEnabled else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        guard let current = try await loadJournal(), Self.sameSubject(current, journal) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let result = try await effects.rebuildPriorPolicyEffect(expected: current, authorization: authorization)
        guard result.operationID == journal.operationID, !result.targetEnabled,
              result.priorPolicy == journal.priorPolicy,
              result.projections == journal.projections,
              result.disposition == .priorPolicyRebuilt,
              try await loadJournal() == result else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try await authorization.validateMutation(operationID: journal.operationID, targetEnabled: false)
        return .priorPolicyRebuilt
    }

    func resolveOpaqueTokenAfterAuthentication(
        _ token: String,
        now: Date, authorization: NotificationOperationAuthorizationV1
    ) async throws -> String? {
        try await authorization.validateRead()
        let result = try await effects.resolveOpaqueTokenEffect(token, now: now, authorization: authorization)
        try await authorization.validateRead()
        return result
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
    private let protectedDataAvailable: @Sendable () async -> Bool
    private let transactionWriter: (any DeviceLocalAppLockSettingPortV1)?

    init(
        preferences: any DevicePreferencesPortV1,
        registry: any SettingsRegistryPortV1,
        protectedDataAvailable: @escaping @Sendable () async -> Bool = {
            await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
        },
        transactionWriter: (any DeviceLocalAppLockSettingPortV1)? = nil
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
        self.protectedDataAvailable = protectedDataAvailable
        self.transactionWriter = transactionWriter
    }

    func readAppLockSetting() async -> DeviceLocalAppLockSettingReadV1 {
        do {
            guard await protectedDataAvailable() else {
                return .protectedDataUnavailable
            }
            guard let data = try preferences.readStoredCanonicalValue(for: descriptor) else {
                let stillAvailable = await protectedDataAvailable()
                return stillAvailable ? .absentDisabled : .protectedDataUnavailable
            }
            let enabled = try CompatibilityCanonicalV1.decode(Bool.self, from: data)
            let value = DeviceLocalAppLockSettingV1(isEnabled: enabled)
            try value.validate()
            let stillAvailable = await protectedDataAvailable()
            return stillAvailable ? .value(value) : .protectedDataUnavailable
        } catch {
            return .corruptOrAmbiguous
        }
    }

    func writeAppLockSetting(
        _ value: DeviceLocalAppLockSettingV1,
        operationID: UUID, authorization: NotificationOperationAuthorizationV1
    ) async throws -> DeviceLocalAppLockSettingWriteReceiptV1 {
        try value.validate()
        try await authorization.validateMutation(operationID: operationID, targetEnabled: value.isEnabled)
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        if let transactionWriter {
            let receipt = try await transactionWriter.writeAppLockSetting(
                value, operationID: operationID, authorization: authorization
            )
            try await authorization.validateMutation(operationID: operationID, targetEnabled: value.isEnabled)
            guard receipt.operationID == operationID, receipt.value == value else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            return receipt
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
        try await authorization.validateMutation(operationID: operationID, targetEnabled: value.isEnabled)
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
        if let transactionWriter {
            try await transactionWriter.eraseAppLockSetting(operationID: operationID)
        } else {
            try preferences.erase(descriptors: [descriptor], operationID: operationID)
        }
        let value = try preferences.readCanonicalValue(for: descriptor)
        guard value == descriptor.defaultCanonicalValue else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }
}

/// Fresh device-local collaborators assembled only by the production
/// composition root after an authentic full-Erase completion. The lifecycle
/// verifies their physical metadata itself before installing them.
struct CompletedEraseAccessReplacementV1: Sendable {
    let subject: EraseAllOperationSubjectV1
    let setting: any DeviceLocalAppLockSettingPortV1
    let ingressStore: any ProtectedIngressStoreV1
    let notifications: any AppLockNotificationPrivacyPortV1
    let notificationControl: AppLockNotificationControlStoreV1
    let clock: any ApplicationClock
}

actor AppLockLifecycleCoordinatorV1 {
    static let shippingAdoption: AppLockShippingAdoptionV1 =
        .deferredUntilAcceptedS10_6Composition

    private let gate: AppAccessGateV1
    private var setting: any DeviceLocalAppLockSettingPortV1
    private var ingress: ProtectedIngressCoordinatorV1
    private var notifications: any AppLockNotificationPrivacyPortV1
    private let identifiers: any ApplicationIDSource
    private var activeOperationID: UUID?
    private var startupSettingUnresolved: Bool
    private var startupHygieneRequiresRecovery: Bool
    private var externalEraseReservation: AppAccessGateV1.EraseAdoptionToken?
    private var retainedCompletedEraseReceipt: CompletedEraseReceiptV1?
    private var retainedAbortedEraseAdmissionReceipt: AbortedEraseAdmissionReceiptV1?

#if DEBUG
    private var configurationPhaseDiagnosticForTesting: (@Sendable (String) -> Void)?
    private var retainedConfigurationPhasesForTesting: [String] = []

    func setConfigurationPhaseDiagnosticForTesting(
        _ observer: (@Sendable (String) -> Void)?
    ) {
        configurationPhaseDiagnosticForTesting = observer
        retainedConfigurationPhasesForTesting.removeAll(keepingCapacity: false)
    }

    func configurationPhasesForTesting() -> [String] {
        retainedConfigurationPhasesForTesting
    }

    private func recordConfigurationPhaseForTesting(_ phase: String) {
        guard let observer = configurationPhaseDiagnosticForTesting else { return }
        if retainedConfigurationPhasesForTesting.count < 32 {
            retainedConfigurationPhasesForTesting.append(phase)
        }
        observer(phase)
    }
#endif

    private init(
        gate: AppAccessGateV1,
        setting: any DeviceLocalAppLockSettingPortV1,
        ingress: ProtectedIngressCoordinatorV1,
        notifications: any AppLockNotificationPrivacyPortV1,
        identifiers: any ApplicationIDSource,
        startupSettingUnresolved: Bool,
        startupHygieneRequiresRecovery: Bool
    ) {
        self.gate = gate
        self.setting = setting
        self.ingress = ingress
        self.notifications = notifications
        self.identifiers = identifiers
        self.startupSettingUnresolved = startupSettingUnresolved
        self.startupHygieneRequiresRecovery = startupHygieneRequiresRecovery
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
        try await notifications.bindNotificationGate(gate)
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
            identifiers: identifiers,
            startupSettingUnresolved: Self.settingIsUnresolved(settingRead),
            startupHygieneRequiresRecovery: hygiene.requiresAuthenticatedRecovery
        )
        let localConfigurationValid = try await notifications.validatesLocalConfiguration(settingRead)
        if !localConfigurationValid {
            await gate.markConfigurationUnknown()
        }
        if hygiene.requiresAuthenticatedRecovery {
            await gate.markConfigurationUnknown()
        }
        return coordinator
    }

    /// C16 production bootstrap composition. Before authentication it can
    /// perform only the ledger's blind metadata expiry purge; content staging
    /// remains fail-closed until the separate durable ingress authority exists.
    static func bootstrap(
        setting: any DeviceLocalAppLockSettingPortV1,
        authentication: any LocalAuthenticationClient,
        ownedStorageLedger: OwnedStorageLedgerV1,
        notifications: any AppLockNotificationPrivacyPortV1,
        clock: any ApplicationClock,
        identifiers: any ApplicationIDSource
    ) async throws -> AppLockLifecycleCoordinatorV1 {
        let effects = OwnedStorageLedgerProtectedIngressEffectV1(ledger: ownedStorageLedger)
        return try await bootstrap(
            setting: setting,
            authentication: authentication,
            ingressStore: InjectedProtectedIngressStoreV1(effects: effects),
            notifications: notifications,
            clock: clock,
            identifiers: identifiers
        )
    }

    func accessGate() -> AppAccessGateV1 { gate }

    /// A nil authorization may only resume the exact admitted cleanup. It
    /// never mints a reservation from current unlocked state or a reused UUID.
    func beginExternalErase(
        subject: EraseAllOperationSubjectV1,
        authorization: AppAccessGateV1.ContentReadToken?
    ) async throws -> AppAccessGateV1.EraseAdoptionToken {
        try validate(subject.eraseID)
        guard activeOperationID == nil else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        if let existing = externalEraseReservation {
            guard existing.subject == subject else {
                throw AppAccessContractFailureV1.invalidTransition
            }
            try await validateExternalEraseReservation(existing)
            return existing
        }
        guard let authorization else {
            throw AppAccessContractFailureV1.accessDenied
        }
        // Hold the lifecycle claim across the gate call, so configuration
        // cannot begin between the original authorization and reservation.
        try claim(subject.eraseID)
        defer { release(subject.eraseID) }
        let reservation = try await gate.reserveEraseAdoption(
            subject: subject, authorization: authorization
        )
        externalEraseReservation = reservation
        return reservation
    }

    func pendingCompletedEraseReceipt() -> CompletedEraseReceiptV1? {
        retainedCompletedEraseReceipt
    }

    func pendingAbortedEraseAdmissionReceipt() -> AbortedEraseAdmissionReceiptV1? {
        retainedAbortedEraseAdmissionReceipt
    }

    func abandonEraseAdmission(_ receipt: AbortedEraseAdmissionReceiptV1) async throws {
        guard let reservation = externalEraseReservation,
              receipt.reservation == reservation, receipt.subject == reservation.subject,
              retainedCompletedEraseReceipt == nil else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try claim(receipt.subject.eraseID)
        defer { release(receipt.subject.eraseID) }
        retainedAbortedEraseAdmissionReceipt = receipt
        try await validateExternalEraseReservation(reservation)
        let currentSetting = await setting.readAppLockSetting()
        try await validateExternalEraseReservation(reservation)
        switch currentSetting {
        case .absentDisabled, .value: break
        case .corruptOrAmbiguous, .protectedDataUnavailable:
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let configurationValid = try await notifications.validatesLocalConfiguration(currentSetting)
        try await validateExternalEraseReservation(reservation)
        let journal = try await notifications.loadJournal()
        try await validateExternalEraseReservation(reservation)
        guard configurationValid,
              Self.verifiesRuntimeConfiguration(setting: currentSetting, journal: journal),
              !startupSettingUnresolved, !startupHygieneRequiresRecovery else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let finalSetting = await setting.readAppLockSetting()
        try await validateExternalEraseReservation(reservation)
        guard finalSetting == currentSetting else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try await gate.abandonEraseAdmission(receipt, setting: finalSetting)
        // The old ingress and notification authorities remain valid because
        // this service receipt proves no Erase effect survives. Keep them.
        externalEraseReservation = nil
        retainedAbortedEraseAdmissionReceipt = nil
    }

    /// Replaces only the authorities whose pinned operational directories
    /// physical Erase removed. This never repeats a destructive erase effect.
    func adoptCompletedErase(
        _ receipt: CompletedEraseReceiptV1,
        replacement: CompletedEraseAccessReplacementV1
    ) async throws {
        guard let reservation = externalEraseReservation,
              receipt.reservation == reservation,
              receipt.subject == reservation.subject,
              replacement.subject == receipt.subject else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        try claim(receipt.subject.eraseID)
        defer { release(receipt.subject.eraseID) }
        // Preserve physical completion before the first suspension. Failure
        // below leaves this receipt and its reservation available for retry.
        retainedCompletedEraseReceipt = receipt
        try await validateExternalEraseReservation(reservation)

        let settingRead = await setting.readAppLockSetting()
        try await validateExternalEraseReservation(reservation)
        guard settingRead == .absentDisabled else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let replacementSettingRead = await replacement.setting.readAppLockSetting()
        try await validateExternalEraseReservation(reservation)
        guard replacementSettingRead == .absentDisabled else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try replacement.notificationControl.requireEmptyForCompletedErase(subject: receipt.subject)
        try await replacement.notifications.bindNotificationGate(gate)
        try await validateExternalEraseReservation(reservation)
        let configurationValid = try await replacement.notifications.validatesLocalConfiguration(settingRead)
        try await validateExternalEraseReservation(reservation)
        guard configurationValid else { throw AppAccessContractFailureV1.configurationUnknown }
        let journal = try await replacement.notifications.loadJournal()
        try await validateExternalEraseReservation(reservation)
        guard journal == nil else { throw AppAccessContractFailureV1.notificationReconciliationRequired }
        let subject = try await replacement.notifications.loadAuthenticationSubject()
        try await validateExternalEraseReservation(reservation)
        guard subject == nil else { throw AppAccessContractFailureV1.notificationReconciliationRequired }

        let hygiene = try await replacement.ingressStore.performBlindStartupHygiene(
            now: replacement.clock.now(), operationID: receipt.subject.eraseID
        )
        try await validateExternalEraseReservation(reservation)
        guard hygiene.operationID == receipt.subject.eraseID, !hygiene.contentRead,
              !hygiene.requiresAuthenticatedRecovery, hygiene.retainedValidCount == 0 else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let pending = try await replacement.ingressStore.pendingIntents()
        try await validateExternalEraseReservation(reservation)
        guard pending.isEmpty else { throw AppAccessContractFailureV1.configurationUnknown }
        let finalSetting = await setting.readAppLockSetting()
        try await validateExternalEraseReservation(reservation)
        guard finalSetting == .absentDisabled else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let finalReplacementSetting = await replacement.setting.readAppLockSetting()
        try await validateExternalEraseReservation(reservation)
        guard finalReplacementSetting == .absentDisabled else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try replacement.notificationControl.requireEmptyForCompletedErase(subject: receipt.subject)

        // Keep the replacement private during the final actor hop: exposing a
        // locked ingress coordinator here would allow staging between the
        // empty readback and adoption. The gate opens only startup recovery;
        // the caller cannot start it until this adoption method returns.
        let replacementIngress = ProtectedIngressCoordinatorV1(gate: gate,
            store: replacement.ingressStore, clock: replacement.clock)
        try await gate.adoptCompletedErase(receipt, token: reservation)
        setting = replacement.setting
        ingress = replacementIngress
        notifications = replacement.notifications
        startupSettingUnresolved = false
        startupHygieneRequiresRecovery = false
        externalEraseReservation = nil
        retainedCompletedEraseReceipt = nil
        retainedAbortedEraseAdmissionReceipt = nil
    }

    private func validateExternalEraseReservation(
        _ reservation: AppAccessGateV1.EraseAdoptionToken
    ) async throws {
        try await gate.validateEraseAdoption(reservation)
        guard externalEraseReservation == reservation else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    private static func settingIsUnresolved(_ read: DeviceLocalAppLockSettingReadV1) -> Bool {
        switch read {
        case .absentDisabled: return false
        case .value(let value): return (try? value.validate()) == nil
        case .corruptOrAmbiguous, .protectedDataUnavailable: return true
        }
    }

    private static func completedJournal(
        _ journal: AppLockNotificationJournalV1,
        matches read: DeviceLocalAppLockSettingReadV1
    ) -> Bool {
        guard case .value(let value) = read,
              (try? value.validate()) != nil,
              value.isEnabled == journal.targetEnabled else { return false }
        if journal.targetEnabled {
            return journal.disposition == .genericProjectionApplied
                || journal.disposition == .genericProjectionAdopted
        }
        return journal.disposition == .priorPolicyRebuilt
    }

    private static func verifiesRuntimeConfiguration(
        setting: DeviceLocalAppLockSettingReadV1,
        journal: AppLockNotificationJournalV1?
    ) -> Bool {
        if let journal { return completedJournal(journal, matches: setting) }
        switch setting {
        case .absentDisabled: return true
        case .value(let value): return (try? value.validate()) != nil && !value.isEnabled
        case .corruptOrAmbiguous, .protectedDataUnavailable: return false
        }
    }

    /// Returns a reason-bearing, nonpersistent permit for a C16 ingress. The
    /// coordinator never caches permits across lock/background transitions.
    func requireContentAccess(
        for surface: AppAccessContentReadSurfaceV1
    ) async throws -> AppAccessContentPermitV1 {
        try await gate.requireContentAccess(for: surface)
    }

    func protectedIngress() -> ProtectedIngressCoordinatorV1 { ingress }

    func resolveNotificationTokenAfterAuthentication(
        _ token: String,
        now: Date
    ) async throws -> String? {
        let sessionID = try await unlockedSessionID()
        let proof = try await gate.beginContentRead(for: .render)
        let authorization = NotificationOperationAuthorizationV1(gate: gate, proof: .content(proof),
            operationID: identifiers.makeID(), subject: nil)
        guard CompatibilityCanonicalV1.validSHA256(token),
              now.timeIntervalSinceReferenceDate.isFinite else {
            throw AppAccessContractFailureV1.invalidValue
        }
        let result = try await notifications.resolveOpaqueTokenAfterAuthentication(
            token,
            now: now, authorization: authorization
        )
        try await requireSameUnlockedSession(sessionID)
        return result
    }

    func enable(operationID: UUID) async throws -> AppLockConfigurationReceiptV1 {
        try validate(operationID)
        try await beginOperation(operationID)
        try claim(operationID, confirmingExisting: true)
        defer { release(operationID); endOperation(operationID) }
        let outcome = await gate.authenticate(trigger: .enableAppLock)
        guard outcome == .authenticated else {
            throw AppAccessContractFailureV1.accessDenied
        }
        let sessionID = try await unlockedSessionID()
        let proof = try await gate.toggleAuthenticationToken(targetEnabled: true)
        do {
            let subject = try await notifications.loadAuthenticationSubject()
            let initialAuthorization = NotificationOperationAuthorizationV1(gate: gate,
                proof: .toggle(proof, targetEnabled: true), operationID: operationID, subject: subject)
            let journal = try await notifications.prepareEnable(operationID: operationID, authorization: initialAuthorization)
            try await requireSameUnlockedSession(sessionID)
            let authorization = try await bind(initialAuthorization, to: journal)
            guard journal.operationID == operationID, journal.targetEnabled,
                  journal.disposition == .enablingPrepared
                    || journal.disposition == .genericProjectionApplied
                    || journal.disposition == .genericProjectionAdopted else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let notification = try await notifications.applyGenericProjection(journal, authorization: authorization)
            try await requireSameUnlockedSession(sessionID)
            guard notification == .genericProjectionApplied
                    || notification == .genericProjectionAdopted else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let write = try await setting.writeAppLockSetting(
                DeviceLocalAppLockSettingV1(isEnabled: true),
                operationID: operationID, authorization: authorization
            )
            try await requireSameUnlockedSession(sessionID)
            guard write.operationID == operationID, write.value.isEnabled else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try await gate.setEnabledAfterAuthenticated(true, toggleToken: proof)
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
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.admission")
#endif
        try validate(operationID)
        try await beginOperation(operationID)
        try claim(operationID, confirmingExisting: true)
        defer { release(operationID); endOperation(operationID) }
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.authentication")
#endif
        let outcome = await gate.authenticate(trigger: .disableAppLock)
#if DEBUG
        recordConfigurationPhaseForTesting("disable.after.authentication")
#endif
        guard outcome == .authenticated else {
            throw AppAccessContractFailureV1.accessDenied
        }
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.unlocked-session")
#endif
        let sessionID = try await unlockedSessionID()
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.toggle-proof")
#endif
        let proof = try await gate.toggleAuthenticationToken(targetEnabled: false)
        do {
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.notification-subject")
#endif
            let subject = try await notifications.loadAuthenticationSubject()
            let initialAuthorization = NotificationOperationAuthorizationV1(gate: gate,
                proof: .toggle(proof, targetEnabled: false), operationID: operationID, subject: subject)
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.notification-prepare")
#endif
            let journal = try await notifications.prepareDisable(operationID: operationID, authorization: initialAuthorization)
            try await requireSameUnlockedSession(sessionID)
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.authorization-bind")
#endif
            let authorization = try await bind(initialAuthorization, to: journal)
            guard journal.operationID == operationID, !journal.targetEnabled,
                  journal.disposition == .disablingPrepared
                    || journal.disposition == .priorPolicyRebuilt else {
                throw AppAccessContractFailureV1.effectMismatch
            }
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.setting-write")
#endif
            let write = try await setting.writeAppLockSetting(
                DeviceLocalAppLockSettingV1(isEnabled: false),
                operationID: operationID, authorization: authorization
            )
            try await requireSameUnlockedSession(sessionID)
            guard write.operationID == operationID, !write.value.isEnabled else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            // Persist the disabled setting before detailed notification state
            // can be restored. A rebuild failure therefore cannot expose
            // details while the durable lock setting is still enabled.
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.notification-rebuild")
#endif
            let notification = try await notifications.rebuildPriorPolicy(journal, authorization: authorization)
            try await requireSameUnlockedSession(sessionID)
            guard notification == .priorPolicyRebuilt else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.gate-setting")
#endif
            try await gate.setEnabledAfterAuthenticated(false, toggleToken: proof)
#if DEBUG
        recordConfigurationPhaseForTesting("disable.before.receipt")
#endif
            return try AppLockConfigurationReceiptV1(
                operationID: operationID,
                enabled: false,
                authenticationOutcome: outcome,
                notificationDisposition: notification,
                settingAdoptedExistingEffect: write.adoptedExistingEffect
            )
        } catch {
#if DEBUG
            recordConfigurationPhaseForTesting("disable.effect-failed")
#endif
            await gate.markConfigurationUnknown()
            throw error
        }
    }

    func recoverAfterAuthentication() async throws -> AppLockRecoveryDispositionV1 {
        let recoveryOperationID = identifiers.makeID()
        try validate(recoveryOperationID)
        try await beginOperation(recoveryOperationID, allowProtectedDataRecovery: true)
        try claim(recoveryOperationID, confirmingExisting: true)
        defer { release(recoveryOperationID); endOperation(recoveryOperationID) }
        // Authentication cannot resolve an unknown filesystem owner. Retain
        // the bootstrap hold until a later validated ownership reconciliation.
        if startupHygieneRequiresRecovery {
            await gate.markConfigurationUnknown()
            return .ambiguousStateLocked
        }
        do {
            // Runtime protected-data loss has no durable Boolean latch.  Read
            // the actual typed setting and validate its notification/journal
            // relationship before releasing the gate's revoking hold.
            let protectedDataGeneration = await gate.protectedDataAvailabilityRecoveryGeneration()
            let currentSetting = await setting.readAppLockSetting()
            let localConfigurationValid = try await notifications.validatesLocalConfiguration(currentSetting)
            let journal = try await notifications.loadJournal()
            if let protectedDataGeneration {
                // Both reads perform concrete availability checks. The second
                // fences loss while notification validation awaited, while the
                // generation rejects a newer runtime loss.
                guard await setting.readAppLockSetting() == currentSetting else {
                    return .ambiguousStateLocked
                }
                do {
                    try await gate.recoverProtectedDataAvailability(
                        setting: currentSetting,
                        configurationVerified: localConfigurationValid
                            && !startupSettingUnresolved
                            && Self.verifiesRuntimeConfiguration(
                                setting: currentSetting, journal: journal
                            ),
                        expectedGeneration: protectedDataGeneration
                    )
                } catch AppAccessContractFailureV1.configurationUnknown {
                    return .ambiguousStateLocked
                } catch AppAccessContractFailureV1.staleAttempt {
                    return .ambiguousStateLocked
                }
            }
            guard let journal else {
                let gateRequiresRecovery = await gate.requiresConfigurationRecovery()
                if startupSettingUnresolved || gateRequiresRecovery || !localConfigurationValid
                    || !Self.verifiesRuntimeConfiguration(setting: currentSetting, journal: nil) {
                    await gate.markConfigurationUnknown()
                    return .ambiguousStateLocked
                }
                return .noRecoveryRequired
            }
            let gateRequiresRecovery = await gate.requiresConfigurationRecovery()
            if !startupSettingUnresolved, !gateRequiresRecovery, localConfigurationValid {
                // This is local configuration readiness only. It does not
                // assert OS reconciliation; that still requires an original
                // authenticated source read on the scheduling/replay route.
                return .noRecoveryRequired
            }
            let subject = try await notifications.loadAuthenticationSubject()
            guard subject?.journal == journal else { throw AppAccessContractFailureV1.effectMismatch }
            await gate.markConfigurationUnknown()
            let outcome = await gate.authenticate(trigger: .repairConfiguration)
            guard outcome == .authenticated else { return .ambiguousStateLocked }
            let proof = try await gate.configurationAuthenticationToken()
            // This rejects a journal replaced during authentication before a
            // preference write. The durable effect still needs its own shared
            // journal/setting transaction fence for cross-instance publication.
            let afterAuthentication = try await notifications.loadJournal()
            try await gate.validateConfigurationAuthentication(proof)
            guard afterAuthentication == journal else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            guard try await notifications.loadAuthenticationSubject() == subject else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let startupRecoveryToken = try await gate.beginConfigurationStartupRecovery(
                proof,
                operationID: journal.operationID
            )
            let authorization = NotificationOperationAuthorizationV1(gate: gate,
                proof: .repair(proof, targetEnabled: journal.targetEnabled),
                operationID: journal.operationID,
                subject: subject,
                startupRecoveryToken: startupRecoveryToken)
            try await authorization.validateRead()
            let notification: AppLockNotificationPrivacyDispositionV1
            if journal.targetEnabled {
                notification = try await notifications.applyGenericProjection(journal, authorization: authorization)
                try await gate.validateConfigurationAuthentication(proof)
                guard notification == .genericProjectionApplied
                        || notification == .genericProjectionAdopted else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
            } else {
                let write = try await setting.writeAppLockSetting(
                    DeviceLocalAppLockSettingV1(isEnabled: false),
                    operationID: journal.operationID, authorization: authorization
                )
                try await gate.validateConfigurationAuthentication(proof)
                guard write.operationID == journal.operationID, !write.value.isEnabled else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                notification = try await notifications.rebuildPriorPolicy(journal, authorization: authorization)
                try await gate.validateConfigurationAuthentication(proof)
                guard notification == .priorPolicyRebuilt else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                try await gate.setEnabledAfterAuthenticated(false, configurationToken: proof)
                startupSettingUnresolved = false
                return write.adoptedExistingEffect
                    ? .adoptedCompletedEffect : .resumedToLocked
            }
            let write = try await setting.writeAppLockSetting(
                DeviceLocalAppLockSettingV1(isEnabled: journal.targetEnabled),
                operationID: journal.operationID, authorization: authorization
            )
            try await gate.validateConfigurationAuthentication(proof)
            guard write.operationID == journal.operationID,
                  write.value.isEnabled == journal.targetEnabled else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try await gate.setEnabledAfterAuthenticated(journal.targetEnabled, configurationToken: proof)
            startupSettingUnresolved = false
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

    private func bind(_ authorization: NotificationOperationAuthorizationV1,
                      to journal: AppLockNotificationJournalV1) async throws -> NotificationOperationAuthorizationV1 {
        guard let subject = try await notifications.loadAuthenticationSubject(), subject.journal == journal else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try await authorization.validateMutation(operationID: journal.operationID, targetEnabled: journal.targetEnabled)
        return try authorization.binding(to: subject)
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
            await gate.markProtectedDataUnavailable()
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
        try await beginOperation(operationID)
        try claim(operationID, confirmingExisting: true)
        defer { release(operationID); endOperation(operationID) }
        try await performErase(operationID: operationID)
    }

    private func performErase(operationID: UUID) async throws {
        guard !startupHygieneRequiresRecovery else {
            await gate.markConfigurationUnknown()
            throw AppAccessContractFailureV1.configurationUnknown
        }
        // Until all configuration effects complete, disabled settings must
        // remain covered too; an ordinary lock intentionally preserves them.
        await gate.markConfigurationUnknown()
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
            startupSettingUnresolved = false
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

    private func beginOperation(_ operationID: UUID, allowProtectedDataRecovery: Bool = false) async throws {
        guard externalEraseReservation == nil else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        try claim(operationID)
        do {
            // After completed Erase, the only permitted recovery exception is
            // the existing typed protected-data readback. Gate authentication
            // and every configuration completion remain denied by the startup
            // barrier; an unresolved physical reservation has no exception.
            try await gate.requireConfigurationMutationAdmission(
                allowProtectedDataRecovery: allowProtectedDataRecovery
            )
        } catch {
            release(operationID)
            throw error
        }
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

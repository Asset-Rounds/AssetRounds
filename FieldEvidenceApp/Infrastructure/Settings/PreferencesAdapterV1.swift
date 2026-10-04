import Foundation

/// Process-local transaction fence shared by control-file publication and the
/// sole preferences adapter. Bodies are synchronous and must never await.
enum AppLockNotificationTransactionFenceV1 {
    private static let lock = NSRecursiveLock()

    static func perform<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

enum PreferencesAdapterFailureV1: Error, Equatable, Sendable {
    case invalidScope
    case invalidCanonicalValue
    case conflictingOperation
    case ambiguousLegacyKeys
}

private struct PreferenceWriteRecordV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let canonicalValueDigest: String
}

private struct PreferenceMigrationRecordV1: Codable, Equatable, Sendable {
    let requestDigest: String
    let legacySourceDigest: String
    let receipt: SettingsMigrationReceiptV1
}

private enum ReminderPolicyOperationKindV1: String, Codable, Sendable {
    case update, reset, erase
}

/// The update case cannot represent a request without live edit authority.
private enum ReminderPolicyChangeV1 {
    case update(AppAccessGateV1.ReminderPolicyEditCommandV1)
    case reset(expected: DeviceLocalReminderPolicyV1, operationID: UUID)
    case erase(expected: DeviceLocalReminderPolicyV1, operationID: UUID)
}

private struct ReminderPolicyOperationV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let kind: ReminderPolicyOperationKindV1
    let expected: DeviceLocalReminderPolicyV1
    let successor: DeviceLocalReminderPolicyV1
    let controlStamp: AppLockReminderPolicyEditStampV1?

    init(operationID: UUID, kind: ReminderPolicyOperationKindV1,
         expected: DeviceLocalReminderPolicyV1, successor: DeviceLocalReminderPolicyV1,
         controlStamp: AppLockReminderPolicyEditStampV1? = nil) {
        self.operationID = operationID; self.kind = kind
        self.expected = expected; self.successor = successor; self.controlStamp = controlStamp
    }

    func validate() throws {
        try expected.validate()
        try successor.validate()
        guard operationID != SettingsValidationV1.zeroUUID,
              expected.revision < UInt64.max,
              successor.instanceID == expected.instanceID,
              successor.revision == expected.revision + 1,
              kind == .update || (!successor.isEnabled && successor.detail == .generic) else {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
        if let controlStamp {
            try controlStamp.validate()
            guard kind == .update, controlStamp.operationID == operationID,
                  controlStamp.expectedPolicy == expected, controlStamp.successorPolicy == successor else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case operationID, kind, expected, successor, controlStamp
    }
    init(from decoder: any Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(operationID: try values.decode(UUID.self, forKey: .operationID),
            kind: try values.decode(ReminderPolicyOperationKindV1.self, forKey: .kind),
            expected: try values.decode(DeviceLocalReminderPolicyV1.self, forKey: .expected),
            successor: try values.decode(DeviceLocalReminderPolicyV1.self, forKey: .successor),
            controlStamp: try values.decodeIfPresent(AppLockReminderPolicyEditStampV1.self, forKey: .controlStamp))
        try validate()
    }
}

private struct PreferenceStorageEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let canonicalValue: Data
    let writeRecord: PreferenceWriteRecordV1?
    let migrationRecord: PreferenceMigrationRecordV1?
    let reminderOperation: ReminderPolicyOperationV1?

    init(
        canonicalValue: Data,
        writeRecord: PreferenceWriteRecordV1? = nil,
        migrationRecord: PreferenceMigrationRecordV1? = nil,
        reminderOperation: ReminderPolicyOperationV1? = nil
    ) {
        schemaVersion = Self.schemaVersion
        self.canonicalValue = canonicalValue
        self.writeRecord = writeRecord
        self.migrationRecord = migrationRecord
        self.reminderOperation = reminderOperation
    }
}

/// Exact legacy storage bytes, including operation and migration metadata.
/// Absence is distinct from an explicitly stored disabled value.
struct AppLockStoredSettingSnapshotV1: Codable, Equatable, Sendable {
    static let maximumEnvelopeBytes = 16_384
    let storedEnvelope: Data?

    init(storedEnvelope: Data?) throws {
        self.storedEnvelope = storedEnvelope
        if let storedEnvelope {
            guard storedEnvelope.count <= Self.maximumEnvelopeBytes else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            let envelope = try Self.decode(storedEnvelope)
            guard try CompatibilityCanonicalV1.encode(envelope) == storedEnvelope else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case storedEnvelope }
    init(from decoder: any Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(storedEnvelope: values.decodeIfPresent(Data.self, forKey: .storedEnvelope))
    }

    fileprivate static func decode(_ bytes: Data) throws -> PreferenceStorageEnvelopeV1 {
        try decodePreferenceStorageEnvelopeV1(bytes, descriptor: SettingsRegistryV1.current()
            .descriptor(for: DeviceLocalAppLockSettingV1.key))
    }

    var setting: DeviceLocalAppLockSettingV1? {
        get throws {
            guard let storedEnvelope else { return nil }
            return try DeviceLocalAppLockSettingV1(isEnabled: CompatibilityCanonicalV1.decode(
                Bool.self, from: Self.decode(storedEnvelope).canonicalValue))
        }
    }
}

struct AppLockSettingWritePlanV1: Codable, Equatable, Sendable {
    let expectedSetting: AppLockStoredSettingSnapshotV1
    let expectedReminderPolicy: DeviceLocalReminderPolicyV1
    let target: DeviceLocalAppLockSettingV1
    let operationID: UUID
    let successor: AppLockStoredSettingSnapshotV1

    init(expectedSetting: AppLockStoredSettingSnapshotV1,
         expectedReminderPolicy: DeviceLocalReminderPolicyV1,
         target: DeviceLocalAppLockSettingV1, operationID: UUID) throws {
        try expectedReminderPolicy.validate()
        try target.validate()
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw PreferencesAdapterFailureV1.conflictingOperation
        }
        let prior = try expectedSetting.storedEnvelope.map(AppLockStoredSettingSnapshotV1.decode)
        // A new plan must not reinterpret an already-used operation ID.
        guard prior?.writeRecord?.operationID != operationID else {
            throw PreferencesAdapterFailureV1.conflictingOperation
        }
        let canonicalValue = try CompatibilityCanonicalV1.encode(target.isEnabled)
        let replacement = PreferenceStorageEnvelopeV1(canonicalValue: canonicalValue,
            writeRecord: .init(operationID: operationID,
                canonicalValueDigest: CompatibilityCanonicalV1.sha256(canonicalValue)),
            migrationRecord: prior?.migrationRecord)
        self.expectedSetting = expectedSetting
        self.expectedReminderPolicy = expectedReminderPolicy
        self.target = target
        self.operationID = operationID
        successor = try .init(storedEnvelope: CompatibilityCanonicalV1.encode(replacement))
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case expectedSetting, expectedReminderPolicy, target, operationID, successor
    }
    init(from decoder: any Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(expectedSetting: values.decode(AppLockStoredSettingSnapshotV1.self, forKey: .expectedSetting),
            expectedReminderPolicy: values.decode(DeviceLocalReminderPolicyV1.self, forKey: .expectedReminderPolicy),
            target: values.decode(DeviceLocalAppLockSettingV1.self, forKey: .target),
            operationID: values.decode(UUID.self, forKey: .operationID))
        guard try values.decode(AppLockStoredSettingSnapshotV1.self, forKey: .successor) == successor else {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
    }
}

/// The rating ledger is deliberately separate from descriptor-backed settings:
/// it is device-local operational policy, not a user-configurable preference.
/// Its write record contains only the caller operation and canonical successor
/// digest needed to make the CAS durable across a process interruption.
private struct RatingEligibilityWriteRecordV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let successorStateSHA256: String
    let receipt: RatingLedgerPersistenceReceiptV1
}

private struct RatingEligibilityStorageEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let state: RatingRequestAttemptLedgerStateV1
    let writeRecord: RatingEligibilityWriteRecordV1

    init(
        state: RatingRequestAttemptLedgerStateV1,
        writeRecord: RatingEligibilityWriteRecordV1
    ) {
        schemaVersion = Self.schemaVersion
        self.state = state
        self.writeRecord = writeRecord
    }
}

private struct RatingEligibilityEnvelopeVersionProbeV1: Codable, Sendable {
    let schemaVersion: Int
}

/// The sole device-local preference adapter. Feature and view code receive the
/// typed port and never read or write raw defaults keys.
final class PreferencesAdapterV1: DevicePreferencesPortV1, RatingEligibilityStoreV1,
    SceneNavigationDeviceStatePortV1,
    @unchecked Sendable {
    static let storagePrefix = "settings.v1."
    private static let ratingEligibilityStorageKey = "rating-eligibility.v1"
    private static let sceneNavigationStorageKey = "scene-navigation.v1"
    private static let ratingEligibilityLock = NSLock()
    private let defaults: UserDefaults
    final class ReminderPolicyEditOwnerV1: Sendable {}
    private let reminderPolicyEditOwner = ReminderPolicyEditOwnerV1()
    private var reminderPolicyEditGate: AppAccessGateV1?
    private weak var reminderPolicyEditControl: AppLockNotificationControlStoreV1?
    private var reminderPolicyEditsRetired = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSceneNavigationData() throws -> Data? {
        try withLock {
            guard let object = defaults.object(forKey: Self.sceneNavigationStorageKey) else { return nil }
            guard let data = object as? Data,
                  data.count <= SceneNavigationSnapshotV1.maximumEncodedByteCount else {
                throw SceneNavigationFailureV1.invalidSnapshot
            }
            return data
        }
    }

    func saveSceneNavigationData(_ data: Data) throws {
        try withLock {
            guard data.count <= SceneNavigationSnapshotV1.maximumEncodedByteCount else {
                throw SceneNavigationFailureV1.invalidSnapshot
            }
            defaults.set(data, forKey: Self.sceneNavigationStorageKey)
            guard defaults.data(forKey: Self.sceneNavigationStorageKey) == data else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
        }
    }

    func eraseSceneNavigationData() throws {
        try withLock {
            defaults.removeObject(forKey: Self.sceneNavigationStorageKey)
            guard defaults.object(forKey: Self.sceneNavigationStorageKey) == nil else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
        }
    }

    func readCanonicalValue(for descriptor: SettingDescriptorV1) throws -> Data {
        try withLock {
            try requireDeviceLocal(descriptor)
            if descriptor.key == DeviceLocalReminderPolicyV1.key,
               defaults.object(forKey: storageKey(descriptor.key)) != nil,
               defaults.data(forKey: storageKey(descriptor.key)) == nil {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            guard let stored = defaults.data(forKey: storageKey(descriptor.key)) else {
                return descriptor.defaultCanonicalValue
            }
            return try decodeEnvelope(stored, descriptor: descriptor).canonicalValue
        }
    }

    func readStoredCanonicalValue(for descriptor: SettingDescriptorV1) throws -> Data? {
        try withLock {
            try requireDeviceLocal(descriptor)
            guard let stored = defaults.object(forKey: storageKey(descriptor.key)) else { return nil }
            guard let data = stored as? Data else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            return try decodeEnvelope(data, descriptor: descriptor).canonicalValue
        }
    }

    func writeCanonicalValue(
        _ value: Data,
        descriptor: SettingDescriptorV1,
        operationID: UUID
    ) throws {
        try withLock {
            try requireDeviceLocal(descriptor)
            try requireGenericMutation(descriptor)
            guard operationID != SettingsValidationV1.zeroUUID else {
                throw PreferencesAdapterFailureV1.conflictingOperation
            }
            try validate(value, descriptor: descriptor)
            let digest = CompatibilityCanonicalV1.sha256(value)
            let prior = try storedEnvelope(for: descriptor)
            if let record = prior?.writeRecord,
               record.operationID == operationID {
                guard record.canonicalValueDigest == digest else {
                    throw PreferencesAdapterFailureV1.conflictingOperation
                }
                return
            }
            let envelope = PreferenceStorageEnvelopeV1(
                canonicalValue: value,
                writeRecord: PreferenceWriteRecordV1(
                    operationID: operationID,
                    canonicalValueDigest: digest
                ),
                migrationRecord: prior?.migrationRecord
            )
            try storeEnvelope(envelope, descriptor: descriptor)
        }
    }

    func migrate(
        descriptor: SettingDescriptorV1,
        legacyKeys: [String],
        operationID: UUID
    ) throws -> SettingsMigrationReceiptV1 {
        try withLock {
            try requireDeviceLocal(descriptor)
            try requireGenericMutation(descriptor)
            guard operationID != SettingsValidationV1.zeroUUID else {
                throw PreferencesAdapterFailureV1.conflictingOperation
            }
            let orderedLegacy = legacyKeys.sorted()
            guard orderedLegacy.count == Set(orderedLegacy).count,
                  orderedLegacy.allSatisfy({
                    SettingsValidationV1.validToken($0, maximumBytes: 160)
                        && !$0.hasPrefix(Self.storagePrefix)
                  }) else {
                throw PreferencesAdapterFailureV1.ambiguousLegacyKeys
            }
            let requestDigest = CompatibilityCanonicalV1.sha256(
                try CompatibilityCanonicalV1.encode([
                    descriptor.key,
                    String(descriptor.migrationVersion),
                ] + orderedLegacy)
            )
            let prior: PreferenceStorageEnvelopeV1?
            if let stored = defaults.data(forKey: storageKey(descriptor.key)) {
                do {
                    prior = try decodeEnvelope(stored, descriptor: descriptor)
                } catch PreferencesAdapterFailureV1.invalidCanonicalValue {
                    prior = nil
                }
            } else {
                prior = nil
            }
            if let prior,
               let migration = prior.migrationRecord,
               migration.receipt.operationID == operationID {
                guard migration.requestDigest == requestDigest else {
                    throw PreferencesAdapterFailureV1.conflictingOperation
                }
                guard migration.receipt.canonicalValueDigest
                        == CompatibilityCanonicalV1.sha256(prior.canonicalValue) else {
                    throw PreferencesAdapterFailureV1.conflictingOperation
                }
                let remainingLegacyDigest = try legacySourceDigest(
                    keys: orderedLegacy,
                    descriptor: descriptor
                )
                if remainingLegacyDigest != Self.emptyLegacySourceDigest,
                   remainingLegacyDigest != migration.legacySourceDigest {
                    throw PreferencesAdapterFailureV1.conflictingOperation
                }
                for key in orderedLegacy { defaults.removeObject(forKey: key) }
                return migration.receipt
            }
            let currentKey = storageKey(descriptor.key)
            let value: Data
            let disposition: SettingsMigrationDispositionV1
            if let current = defaults.data(forKey: currentKey) {
                do {
                    value = try decodeEnvelope(current, descriptor: descriptor).canonicalValue
                    disposition = .adoptedCurrentValue
                } catch {
                    value = descriptor.defaultCanonicalValue
                    disposition = .replacedInvalidLegacyWithDefault
                }
            } else {
                let candidates = try orderedLegacy.compactMap { key -> Data? in
                    try legacyCanonicalValue(forKey: key, descriptor: descriptor)
                }
                guard candidates.count <= 1 else {
                    throw PreferencesAdapterFailureV1.ambiguousLegacyKeys
                }
                if let candidate = candidates.first {
                    do {
                        try validate(candidate, descriptor: descriptor)
                        value = candidate
                        disposition = .migratedLegacyValue
                    } catch {
                        value = descriptor.defaultCanonicalValue
                        disposition = .replacedInvalidLegacyWithDefault
                    }
                } else {
                    value = descriptor.defaultCanonicalValue
                    disposition = .initializedFromAbsence
                }
            }
            let legacyDigest = try legacySourceDigest(
                keys: orderedLegacy,
                descriptor: descriptor
            )
            let receipt = try SettingsMigrationReceiptV1(
                operationID: operationID,
                key: descriptor.key,
                migrationVersion: descriptor.migrationVersion,
                disposition: disposition,
                canonicalValueDigest: CompatibilityCanonicalV1.sha256(value)
            )
            let envelope = PreferenceStorageEnvelopeV1(
                canonicalValue: value,
                migrationRecord: PreferenceMigrationRecordV1(
                    requestDigest: requestDigest,
                    legacySourceDigest: legacyDigest,
                    receipt: receipt
                )
            )
            try storeEnvelope(envelope, descriptor: descriptor)
            for key in orderedLegacy { defaults.removeObject(forKey: key) }
            return receipt
        }
    }

    func reset(descriptors: [SettingDescriptorV1], operationID: UUID) throws {
        try replaceWithDefaults(
            descriptors: descriptors,
            operationID: operationID,
            preserveAcknowledgements: true
        )
    }

    func erase(descriptors: [SettingDescriptorV1], operationID: UUID) throws {
        try replaceWithDefaults(
            descriptors: descriptors,
            operationID: operationID,
            preserveAcknowledgements: false
        )
    }

    // MARK: - Device-local reminder policy

    /// Unlike readReminderPolicy, this never creates a default or identity.
    func readStoredReminderPolicy() throws -> DeviceLocalReminderPolicyV1? {
        try withLock {
            let descriptor = try SettingsRegistryV1.current().descriptor(for: DeviceLocalReminderPolicyV1.key)
            guard let envelope = try reminderEnvelope(descriptor: descriptor) else { return nil }
            return try CompatibilityCanonicalV1.decode(DeviceLocalReminderPolicyV1.self, from: envelope.canonicalValue)
        }
    }

    func readAppLockSettingSnapshot() throws -> AppLockStoredSettingSnapshotV1 {
        try withLock {
            let key = storageKey(DeviceLocalAppLockSettingV1.key)
            guard let object = defaults.object(forKey: key) else { return try .init(storedEnvelope: nil) }
            guard let bytes = object as? Data else { throw PreferencesAdapterFailureV1.invalidCanonicalValue }
            return try .init(storedEnvelope: bytes)
        }
    }

    func planAppLockSettingWrite(expectedSetting: AppLockStoredSettingSnapshotV1,
        expectedReminderPolicy: DeviceLocalReminderPolicyV1,
        target: DeviceLocalAppLockSettingV1, operationID: UUID) throws -> AppLockSettingWritePlanV1 {
        try withLock {
            guard try readAppLockSettingSnapshot() == expectedSetting,
                  try readStoredReminderPolicy() == expectedReminderPolicy else {
                throw SettingsContractFailureV1.staleRevision
            }
            return try .init(expectedSetting: expectedSetting, expectedReminderPolicy: expectedReminderPolicy,
                target: target, operationID: operationID)
        }
    }

    func applyAppLockSettingWrite(_ plan: AppLockSettingWritePlanV1) throws -> AppLockStoredSettingSnapshotV1 {
        try withLock {
            guard try readStoredReminderPolicy() == plan.expectedReminderPolicy else {
                throw SettingsContractFailureV1.staleRevision
            }
            let current = try readAppLockSettingSnapshot()
            if current == plan.successor { return current }
            guard current == plan.expectedSetting, let bytes = plan.successor.storedEnvelope else {
                throw SettingsContractFailureV1.staleRevision
            }
            defaults.set(bytes, forKey: storageKey(DeviceLocalAppLockSettingV1.key))
            let readback = try readAppLockSettingSnapshot()
            guard readback == plan.successor else { throw PreferencesAdapterFailureV1.invalidCanonicalValue }
            return readback
        }
    }

    func readReminderPolicy() throws -> DeviceLocalReminderPolicyV1 {
        try withLock {
            let descriptor = try SettingsRegistryV1.current().descriptor(for: DeviceLocalReminderPolicyV1.key)
            if let envelope = try reminderEnvelope(descriptor: descriptor) {
                return try CompatibilityCanonicalV1.decode(DeviceLocalReminderPolicyV1.self, from: envelope.canonicalValue)
            }
            let policy = try DeviceLocalReminderPolicyV1(instanceID: UUID(), revision: 1,
                                                        isEnabled: false, detail: .generic)
            let envelope = PreferenceStorageEnvelopeV1(canonicalValue: try CompatibilityCanonicalV1.encode(policy))
            try storeReminderEnvelope(envelope, descriptor: descriptor)
            return policy
        }
    }

    func bindReminderPolicyEdits(to gate: AppAccessGateV1,
                                control: AppLockNotificationControlStoreV1) throws {
        try withLock {
            guard reminderPolicyEditGate == nil, !reminderPolicyEditsRetired else {
                throw AppAccessContractFailureV1.accessDenied
            }
            try control.requirePreferencesOwner(self)
            try control.verifyNotificationStorage()
            reminderPolicyEditGate = gate
            reminderPolicyEditControl = control
        }
    }

    func retireReminderPolicyEdits() {
        AppLockNotificationTransactionFenceV1.perform { reminderPolicyEditsRetired = true }
    }

    func authorizeReminderPolicyEdit(_ request: ReminderPolicyEditRequestV1) async throws -> AppAccessGateV1.ReminderPolicyEditCommandV1 {
        let gate = try withLock {
            guard let gate = reminderPolicyEditGate, !reminderPolicyEditsRetired else {
                throw AppAccessContractFailureV1.accessDenied
            }
            return gate
        }
        // Release the preferences fence before entering the actor. The leaf
        // independently rechecks owner retirement after this await.
        return try await gate.authorizeReminderPolicyEdit(request, owner: reminderPolicyEditOwner)
    }

    func updateReminderPolicy(_ command: AppAccessGateV1.ReminderPolicyEditCommandV1) throws -> DeviceLocalReminderPolicyV1 {
        try changeReminderPolicy(.update(command))
    }

    func resetReminderPolicy(expected: DeviceLocalReminderPolicyV1,
                             operationID: UUID) throws -> DeviceLocalReminderPolicyV1 {
        try changeReminderPolicy(.reset(expected: expected, operationID: operationID))
    }

    func eraseReminderPolicy(expected: DeviceLocalReminderPolicyV1,
                             operationID: UUID) throws -> DeviceLocalReminderPolicyV1 {
        try changeReminderPolicy(.erase(expected: expected, operationID: operationID))
    }

    /// Durable effect evidence only. Reading it never repeats a preference write.
    func completedReminderControlEdit() throws -> AppLockReminderPolicyEditStampV1? {
        try withLock {
            let descriptor = try SettingsRegistryV1.current().descriptor(for: DeviceLocalReminderPolicyV1.key)
            guard let envelope = try reminderEnvelope(descriptor: descriptor),
                  let operation = envelope.reminderOperation else { return nil }
            try operation.validate()
            guard operation.kind == .update else { return nil }
            return operation.controlStamp
        }
    }

    private func changeReminderPolicy(_ change: ReminderPolicyChangeV1) throws -> DeviceLocalReminderPolicyV1 {
        // Called only while the preferences transaction fence is held. Update
        // authority is checked before any envelope read, including a replay.
        func apply(expected: DeviceLocalReminderPolicyV1, isEnabled: Bool,
                   detail: ReminderNotificationDetailV1, kind: ReminderPolicyOperationKindV1,
                   operationID: UUID,
                   controlStamp: AppLockReminderPolicyEditStampV1? = nil) throws -> DeviceLocalReminderPolicyV1 {
            try expected.validate()
            guard operationID != SettingsValidationV1.zeroUUID, expected.revision < UInt64.max else {
                throw SettingsContractFailureV1.invalidValue
            }
            let descriptor = try SettingsRegistryV1.current().descriptor(for: DeviceLocalReminderPolicyV1.key)
            guard let prior = try reminderEnvelope(descriptor: descriptor) else {
                throw SettingsContractFailureV1.staleRevision
            }
            let successor = try DeviceLocalReminderPolicyV1(instanceID: expected.instanceID,
                revision: expected.revision + 1, isEnabled: isEnabled, detail: detail)
            let request = ReminderPolicyOperationV1(operationID: operationID, kind: kind,
                expected: expected, successor: successor, controlStamp: controlStamp)
            try request.validate()
            if let original = prior.reminderOperation, original.operationID == operationID {
                guard original == request else { throw SettingsContractFailureV1.changedOperation }
                return original.successor
            }
            let current = try CompatibilityCanonicalV1.decode(DeviceLocalReminderPolicyV1.self, from: prior.canonicalValue)
            guard current == expected else { throw SettingsContractFailureV1.staleRevision }
            try storeReminderEnvelope(PreferenceStorageEnvelopeV1(
                canonicalValue: try CompatibilityCanonicalV1.encode(successor), reminderOperation: request
            ), descriptor: descriptor)
            return successor
        }
        switch change {
        case .update(let command):
            let gate = try withLock {
                guard let gate = reminderPolicyEditGate, !reminderPolicyEditsRetired else {
                    throw AppAccessContractFailureV1.accessDenied
                }
                return gate
            }
            guard gate.issuedReminderPolicyEditCommand(command) else {
                throw AppAccessContractFailureV1.accessDenied
            }
            // Reference first, preferences fence second. Neither lock body
            // awaits or calls back into the gate.
            return try command.withReminderPolicyEdit(owner: reminderPolicyEditOwner) {
                try withLock {
                    guard reminderPolicyEditGate === gate, !reminderPolicyEditsRetired,
                          let control = reminderPolicyEditControl else {
                        throw AppAccessContractFailureV1.accessDenied
                    }
                    try control.requirePreferencesOwner(self)
                    let currentControl = try control.readyControlForReminderPolicy()
                    let request = command.request
                    let descriptor = try SettingsRegistryV1.current().descriptor(for: DeviceLocalReminderPolicyV1.key)
                    let prior = try reminderEnvelope(descriptor: descriptor)
                    if let operation = prior?.reminderOperation, operation.operationID == request.operationID {
                        try operation.validate()
                        guard operation.kind == .update, operation.expected == request.expected,
                              operation.successor.isEnabled == request.isEnabled,
                              operation.successor.detail == request.detail,
                              currentControl?.reminderPolicyContinuation == operation.controlStamp,
                              (currentControl == nil) == (operation.controlStamp == nil) else {
                            throw SettingsContractFailureV1.changedOperation
                        }
                        return operation.successor
                    }
                    let stamp = try control.reminderPolicyEditStamp(for: request, expected: currentControl)
                    let result = try apply(expected: request.expected, isEnabled: request.isEnabled,
                        detail: request.detail, kind: .update, operationID: request.operationID,
                        controlStamp: stamp)
                    try control.afterReminderPolicyWrite()
                    _ = try control.readyControlForReminderPolicy()
                    return result
                }
            }
        case .reset(let expected, let operationID):
            return try withLock {
                try apply(expected: expected, isEnabled: false, detail: .generic,
                    kind: .reset, operationID: operationID)
            }
        case .erase(let expected, let operationID):
            return try withLock {
                try apply(expected: expected, isEnabled: false, detail: .generic,
                    kind: .erase, operationID: operationID)
            }
        }
    }

    private func reminderEnvelope(descriptor: SettingDescriptorV1) throws -> PreferenceStorageEnvelopeV1? {
        guard let object = defaults.object(forKey: storageKey(descriptor.key)) else { return nil }
        guard let data = object as? Data else { throw PreferencesAdapterFailureV1.invalidCanonicalValue }
        return try decodeEnvelope(data, descriptor: descriptor)
    }

    private func storeReminderEnvelope(_ envelope: PreferenceStorageEnvelopeV1,
                                       descriptor: SettingDescriptorV1) throws {
        let bytes = try CompatibilityCanonicalV1.encode(envelope)
        _ = try decodeEnvelope(bytes, descriptor: descriptor)
        defaults.set(bytes, forKey: storageKey(descriptor.key))
        guard defaults.data(forKey: storageKey(descriptor.key)) == bytes,
              try reminderEnvelope(descriptor: descriptor) == envelope else {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
    }

    // MARK: - C39 device-local rating eligibility ledger

    func load() async throws -> RatingLedgerLoadResultV1 {
        try withRatingEligibilityLock { ratingEligibilityLoadResultLocked() }
    }

    func compareAndSwap(
        operationID: UUID,
        expectedRevision: UInt64?,
        successor: RatingRequestAttemptLedgerStateV1
    ) async throws -> RatingLedgerPersistenceReceiptV1 {
        try withRatingEligibilityLock {
            guard operationID != SettingsValidationV1.zeroUUID else {
                throw RatingEligibilityFailureV1.invalidValue
            }
            try validateRatingEligibilityState(successor)

            switch ratingEligibilityLoadResultLocked() {
            case .absentFreshInstall:
                guard expectedRevision == nil, successor.revision == 1 else {
                    throw RatingEligibilityFailureV1.staleState
                }
            case .current(let current):
                guard let persisted = ratingEligibilityCurrentEnvelopeLocked(),
                      persisted.state == current else {
                    throw RatingEligibilityFailureV1.storageUnavailable
                }
                if persisted.writeRecord.operationID == operationID {
                    guard persisted.writeRecord.successorStateSHA256 == successor.stateSHA256,
                          persisted.writeRecord.receipt.resultingRevision == successor.revision,
                          persisted.writeRecord.receipt.stateSHA256 == successor.stateSHA256 else {
                        throw RatingEligibilityFailureV1.divergentReplay
                    }
                    return RatingLedgerPersistenceReceiptV1(
                        operationID: operationID,
                        expectedRevision: persisted.writeRecord.receipt.expectedRevision,
                        resultingRevision: persisted.writeRecord.receipt.resultingRevision,
                        stateSHA256: persisted.writeRecord.receipt.stateSHA256,
                        disposition: .idempotentReplay
                    )
                }
                guard expectedRevision == current.revision,
                      successor.revision == current.revision + 1 else {
                    throw RatingEligibilityFailureV1.staleState
                }
            case .corrupt, .futureVersion, .migrationFailed:
                throw RatingEligibilityFailureV1.storageUnavailable
            }

            let receipt = RatingLedgerPersistenceReceiptV1(
                operationID: operationID,
                expectedRevision: expectedRevision,
                resultingRevision: successor.revision,
                stateSHA256: successor.stateSHA256,
                disposition: .committed
            )
            let envelope = RatingEligibilityStorageEnvelopeV1(
                state: successor,
                writeRecord: RatingEligibilityWriteRecordV1(
                    operationID: operationID,
                    successorStateSHA256: successor.stateSHA256,
                    receipt: receipt
                )
            )
            let data = try CompatibilityCanonicalV1.encode(envelope)
            defaults.set(data, forKey: Self.ratingEligibilityStorageKey)

            guard let persisted = ratingEligibilityCurrentEnvelopeLocked(),
                  persisted.state == successor,
                  persisted.writeRecord.receipt == receipt else {
                throw RatingEligibilityFailureV1.storageUnavailable
            }
            return receipt
        }
    }

    /// Recovery may retain an already-persisted Erase cooldown only when this
    /// exact Erase operation owns the canonical ledger and nothing else
    /// remains in the injected Defaults domain. Any mismatch forces the
    /// normal full-domain wipe before a replacement is written.
    func hasExactEraseCooldown(
        operationID: UUID,
        persistentDomainName: String
    ) -> Bool {
        (try? withRatingEligibilityLock {
            guard operationID != SettingsValidationV1.zeroUUID,
                  let domain = defaults.persistentDomain(forName: persistentDomainName),
                  Set(domain.keys) == Set([Self.ratingEligibilityStorageKey]),
                  case .current(let state) = ratingEligibilityLoadResultLocked(),
                  let envelope = ratingEligibilityCurrentEnvelopeLocked(),
                  envelope.state == state,
                  envelope.writeRecord.operationID == operationID,
                  envelope.writeRecord.receipt.operationID == operationID,
                  envelope.writeRecord.receipt.expectedRevision == nil,
                  envelope.writeRecord.receipt.resultingRevision == state.revision,
                  envelope.writeRecord.receipt.stateSHA256 == state.stateSHA256,
                  envelope.writeRecord.successorStateSHA256 == state.stateSHA256,
                  state.attempts.isEmpty,
                  case .erasedCooldown = state.origin else {
                return false
            }
            return true
        }) ?? false
    }

    /// Serializes only the exact-cooldown check and conditional domain wipe.
    /// The later awaited rating completion and OS effects are separate work.
    @discardableResult
    func preparePreferencesForCompletedErase(operationID: UUID,
        persistentDomainName: String) throws -> Bool {
        try withLock {
            guard operationID != SettingsValidationV1.zeroUUID, !persistentDomainName.isEmpty else {
                throw PreferencesAdapterFailureV1.conflictingOperation
            }
            if hasExactEraseCooldown(operationID: operationID, persistentDomainName: persistentDomainName) {
                return true
            }
            defaults.removePersistentDomain(forName: persistentDomainName)
            guard defaults.persistentDomain(forName: persistentDomainName)?.isEmpty != false else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            return false
        }
    }

    private func replaceWithDefaults(
        descriptors: [SettingDescriptorV1],
        operationID: UUID,
        preserveAcknowledgements: Bool
    ) throws {
        try withLock {
            guard operationID != SettingsValidationV1.zeroUUID,
                  Set(descriptors.map(\.key)).count == descriptors.count else {
                throw PreferencesAdapterFailureV1.conflictingOperation
            }
            try descriptors.forEach(requireGenericMutation)
            for descriptor in descriptors.sorted(by: { $0.key < $1.key }) {
                try requireDeviceLocal(descriptor)
                if preserveAcknowledgements,
                   descriptor.reset == .preserveAcknowledgement { continue }
                if SurveyDefinitionDeviceMemoryV1.isPreferenceKey(descriptor.key) {
                    // Favorites and recents are disposable device memory.  A
                    // reset or erase removes the envelope rather than
                    // retaining a stale release pointer or preference bytes.
                    defaults.removeObject(forKey: storageKey(descriptor.key))
                    continue
                }
                try validate(descriptor.defaultCanonicalValue, descriptor: descriptor)
                try storeEnvelope(
                    PreferenceStorageEnvelopeV1(
                        canonicalValue: descriptor.defaultCanonicalValue
                    ),
                    descriptor: descriptor
                )
            }
        }
    }

    private func validate(_ data: Data, descriptor: SettingDescriptorV1) throws {
        do {
            try descriptor.validateCanonicalValue(data)
        } catch {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
    }

    private func requireDeviceLocal(_ descriptor: SettingDescriptorV1) throws {
        try descriptor.validate()
        guard descriptor.scope == .deviceLocal,
              descriptor.storage == .soleDevicePreferencesAdapter,
              !SurveySessionDevicePersistenceBoundaryV1.isCanonicalFactKey(descriptor.key) else {
            throw PreferencesAdapterFailureV1.invalidScope
        }
    }

    private func requireGenericMutation(_ descriptor: SettingDescriptorV1) throws {
        guard descriptor.key != DeviceLocalReminderPolicyV1.key else {
            throw PreferencesAdapterFailureV1.invalidScope
        }
    }

    private func legacyCanonicalValue(
        forKey key: String,
        descriptor: SettingDescriptorV1
    ) throws -> Data? {
        guard let object = defaults.object(forKey: key) else { return nil }
        if let data = object as? Data { return data }
        if descriptor.valueKind == .boolean, let value = object as? Bool {
            return try CompatibilityCanonicalV1.encode(value)
        }
        return Data("unsupported-property-list-type".utf8)
    }

    private static let emptyLegacySourceDigest =
        "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"

    private func legacySourceDigest(
        keys: [String],
        descriptor: SettingDescriptorV1
    ) throws -> String {
        let rows = try keys.compactMap { key -> String? in
            guard let value = try legacyCanonicalValue(forKey: key, descriptor: descriptor) else {
                return nil
            }
            return key + "=" + CompatibilityCanonicalV1.sha256(value)
        }
        return CompatibilityCanonicalV1.sha256(try CompatibilityCanonicalV1.encode(rows))
    }

    private func storedEnvelope(
        for descriptor: SettingDescriptorV1
    ) throws -> PreferenceStorageEnvelopeV1? {
        guard let data = defaults.data(forKey: storageKey(descriptor.key)) else { return nil }
        return try decodeEnvelope(data, descriptor: descriptor)
    }

    private func decodeEnvelope(
        _ data: Data,
        descriptor: SettingDescriptorV1
    ) throws -> PreferenceStorageEnvelopeV1 {
        try decodePreferenceStorageEnvelopeV1(data, descriptor: descriptor)
    }

    private func storeEnvelope(
        _ envelope: PreferenceStorageEnvelopeV1,
        descriptor: SettingDescriptorV1
    ) throws {
        try validate(envelope.canonicalValue, descriptor: descriptor)
        defaults.set(
            try CompatibilityCanonicalV1.encode(envelope),
            forKey: storageKey(descriptor.key)
        )
    }

    private func storageKey(_ key: String) -> String { Self.storagePrefix + key }

    private func ratingEligibilityLoadResultLocked() -> RatingLedgerLoadResultV1 {
        guard let object = defaults.object(forKey: Self.ratingEligibilityStorageKey) else {
            return .absentFreshInstall
        }
        guard let data = object as? Data else { return .corrupt }
        do {
            // The probe intentionally does not require the full current
            // envelope shape: it is how a newer or prior schema is kept
            // distinct from malformed current bytes.
            let version = try JSONDecoder().decode(
                RatingEligibilityEnvelopeVersionProbeV1.self,
                from: data
            ).schemaVersion
            if version > RatingEligibilityStorageEnvelopeV1.schemaVersion {
                return .futureVersion
            }
            if version < RatingEligibilityStorageEnvelopeV1.schemaVersion {
                return .migrationFailed
            }
            let envelope = try CompatibilityCanonicalV1.decode(
                RatingEligibilityStorageEnvelopeV1.self,
                from: data
            )
            guard envelope.schemaVersion == RatingEligibilityStorageEnvelopeV1.schemaVersion else {
                return .corrupt
            }
            try validateRatingEligibilityState(envelope.state)
            guard envelope.writeRecord.operationID != SettingsValidationV1.zeroUUID,
                  KernelCanonicalHashV1.validSHA256(
                    envelope.writeRecord.successorStateSHA256
                  ),
                  envelope.writeRecord.successorStateSHA256 == envelope.state.stateSHA256,
                  envelope.writeRecord.receipt.operationID
                    == envelope.writeRecord.operationID,
                  envelope.writeRecord.receipt.resultingRevision
                    == envelope.state.revision,
                  envelope.writeRecord.receipt.stateSHA256
                    == envelope.state.stateSHA256,
                  envelope.writeRecord.receipt.expectedRevision
                    == (envelope.state.revision == 1 ? nil : envelope.state.revision - 1),
                  envelope.writeRecord.receipt.disposition == .committed else {
                return .corrupt
            }
            return .current(envelope.state)
        } catch {
            return .corrupt
        }
    }

    private func ratingEligibilityCurrentEnvelopeLocked()
        -> RatingEligibilityStorageEnvelopeV1? {
        guard let data = defaults.data(forKey: Self.ratingEligibilityStorageKey),
              let envelope = try? CompatibilityCanonicalV1.decode(
                RatingEligibilityStorageEnvelopeV1.self,
                from: data
              ),
              envelope.schemaVersion == RatingEligibilityStorageEnvelopeV1.schemaVersion,
              (try? validateRatingEligibilityState(envelope.state)) != nil else {
            return nil
        }
        return envelope
    }

    private func validateRatingEligibilityState(
        _ state: RatingRequestAttemptLedgerStateV1
    ) throws {
        try state.validate()
        guard state.clockHighWatermarkUTC
            >= (state.attempts.map(\.reservedAt).max() ?? .distantPast) else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        if case .erasedCooldown(let erasedAt, let suppressUntil) = state.origin {
            guard erasedAt.timeIntervalSinceReferenceDate.isFinite,
                  suppressUntil.timeIntervalSinceReferenceDate.isFinite,
                  state.attempts.isEmpty,
                  suppressUntil == erasedAt.addingTimeInterval(
                    RatingEligibilityPolicyV1.eraseCooldownSeconds
                  ),
                  state.clockHighWatermarkUTC >= erasedAt else {
                throw RatingEligibilityFailureV1.invalidValue
            }
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try AppLockNotificationTransactionFenceV1.perform(body)
    }

    private func withRatingEligibilityLock<T>(_ body: () throws -> T) throws -> T {
        try AppLockNotificationTransactionFenceV1.perform {
            Self.ratingEligibilityLock.lock()
            defer { Self.ratingEligibilityLock.unlock() }
            return try body()
        }
    }
}

extension PreferencesAdapterV1 {
    func activeWorkspaceSelection() throws -> ActiveWorkspaceSelectionV1? {
        let descriptor = try SettingsRegistryV1.current().descriptor(
            for: WorkspaceExperienceDevicePreferenceV1.activeWorkspaceSelectionKey
        )
        guard descriptor.valueKind == .workspaceExperienceSelection else {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
        let value = try CompatibilityCanonicalV1.decode(
            ActiveWorkspaceSelectionV1?.self,
            from: readCanonicalValue(for: descriptor)
        )
        try value?.validate()
        return value
    }

    func setActiveWorkspaceSelection(
        _ value: ActiveWorkspaceSelectionV1?,
        operationID: UUID
    ) throws {
        try value?.validate()
        let descriptor = try SettingsRegistryV1.current().descriptor(
            for: WorkspaceExperienceDevicePreferenceV1.activeWorkspaceSelectionKey
        )
        try writeCanonicalValue(
            CompatibilityCanonicalV1.encode(value), descriptor: descriptor, operationID: operationID
        )
    }

    func noticeAcknowledgement() throws -> NoticeAcknowledgementV1? {
        let descriptor = try SettingsRegistryV1.current().descriptor(
            for: WorkspaceExperienceDevicePreferenceV1.noticeAcknowledgementKey
        )
        guard descriptor.valueKind == .workspaceExperienceNoticeAcknowledgement else {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
        return try CompatibilityCanonicalV1.decode(
            NoticeAcknowledgementV1?.self,
            from: readCanonicalValue(for: descriptor)
        )
    }

    func setNoticeAcknowledgement(
        _ value: NoticeAcknowledgementV1?,
        operationID: UUID
    ) throws {
        let descriptor = try SettingsRegistryV1.current().descriptor(
            for: WorkspaceExperienceDevicePreferenceV1.noticeAcknowledgementKey
        )
        try writeCanonicalValue(
            CompatibilityCanonicalV1.encode(value), descriptor: descriptor, operationID: operationID
        )
    }

    func readPrivateSystemDiscoveryOptIn() throws -> PrivateSystemDiscoveryOptInV1 {
        let descriptor = try SettingsRegistryV1.current().descriptor(for: PrivateSystemDiscoveryOptInV1.settingKey)
        let token = try CompatibilityCanonicalV1.decode(String.self, from: readCanonicalValue(for: descriptor))
        return try PrivateSystemDiscoveryOptInV1(canonicalSettingToken: token,
            workspaceKind: token == PrivateSystemDiscoveryOptInV1.offToken ? nil : .real)
    }

    func writePrivateSystemDiscoveryOptIn(_ value: PrivateSystemDiscoveryOptInV1, operationID: UUID) throws {
        try value.validate()
        let descriptor = try SettingsRegistryV1.current().descriptor(for: PrivateSystemDiscoveryOptInV1.settingKey)
        try writeCanonicalValue(CompatibilityCanonicalV1.encode(value.canonicalSettingToken),
            descriptor: descriptor, operationID: operationID)
    }

    func migratePrivateSystemDiscoveryOptIn(operationID: UUID) throws -> PrivateSystemDiscoveryOptInV1 {
        let value = try readPrivateSystemDiscoveryOptIn()
        try writePrivateSystemDiscoveryOptIn(value, operationID: operationID)
        return value
    }
}

// MARK: - C25 device-local survey-definition memory

extension PreferencesAdapterV1 {
    func readSurveyDefinitionFavoriteReferences() throws
        -> [SurveyDefinitionPreferenceReferenceV1] {
        try readSurveyDefinitionReferences(for: SurveyDefinitionDeviceMemoryV1.favoriteKey)
    }

    func writeSurveyDefinitionFavoriteReferences(
        _ values: [SurveyDefinitionPreferenceReferenceV1],
        operationID: UUID
    ) throws {
        try writeSurveyDefinitionReferences(
            values,
            key: SurveyDefinitionDeviceMemoryV1.favoriteKey,
            operationID: operationID
        )
    }

    func readSurveyDefinitionRecentReferences() throws
        -> [SurveyDefinitionPreferenceReferenceV1] {
        try readSurveyDefinitionReferences(for: SurveyDefinitionDeviceMemoryV1.recentsKey)
    }

    func writeSurveyDefinitionRecentReferences(
        _ values: [SurveyDefinitionPreferenceReferenceV1],
        operationID: UUID
    ) throws {
        try writeSurveyDefinitionReferences(
            values,
            key: SurveyDefinitionDeviceMemoryV1.recentsKey,
            operationID: operationID
        )
    }

    /// Compatibility spelling for callers that only display stable IDs.  The
    /// stored value remains the typed reference array and this bridge rejects
    /// arbitrary strings before they reach the adapter.
    func readSurveyDefinitionFavoriteIDs() throws -> [String] {
        try readSurveyDefinitionFavoriteReferences().map(\.stableStorageID)
    }

    func writeSurveyDefinitionFavoriteIDs(
        _ values: [String],
        operationID: UUID
    ) throws {
        try writeSurveyDefinitionFavoriteReferences(
            try SurveyDefinitionDeviceMemoryV1.references(
                fromStableStorageIDs: values,
                recencyOrdered: false
            ),
            operationID: operationID
        )
    }

    func readSurveyDefinitionRecentIDs() throws -> [String] {
        try readSurveyDefinitionRecentReferences().map(\.stableStorageID)
    }

    func writeSurveyDefinitionRecentIDs(
        _ values: [String],
        operationID: UUID
    ) throws {
        try writeSurveyDefinitionRecentReferences(
            try SurveyDefinitionDeviceMemoryV1.references(
                fromStableStorageIDs: values,
                recencyOrdered: true
            ),
            operationID: operationID
        )
    }

    private func readSurveyDefinitionReferences(
        for key: String
    ) throws -> [SurveyDefinitionPreferenceReferenceV1] {
        let descriptor = try SettingsRegistryV1.current().descriptor(for: key)
        guard descriptor.valueKind == .surveyDefinitionPreferenceReferenceSet else {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
        let data = try readCanonicalValue(for: descriptor)
        let values = try CompatibilityCanonicalV1.decode(
            [SurveyDefinitionPreferenceReferenceV1].self,
            from: data
        )
        let canonical = try SurveyDefinitionDeviceMemoryV1.canonicalReferences(
            values,
            forKey: key
        )
        guard canonical == values else {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
        return values
    }

    private func writeSurveyDefinitionReferences(
        _ values: [SurveyDefinitionPreferenceReferenceV1],
        key: String,
        operationID: UUID
    ) throws {
        let canonical = try SurveyDefinitionDeviceMemoryV1.canonicalReferences(
            values,
            forKey: key
        )
        let descriptor = try SettingsRegistryV1.current().descriptor(for: key)
        try writeCanonicalValue(
            CompatibilityCanonicalV1.encode(canonical),
            descriptor: descriptor,
            operationID: operationID
        )
    }
}

enum C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Settings_PreferencesAdapterV1_swift {
    static let integrationRole = "DEVICE_POLICY_NOT_CANONICAL_TRUTH"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let createsSecondRouteOrInspectionAlias = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

// Shared validation preserves the existing descriptor/envelope wire contract.
private func decodePreferenceStorageEnvelopeV1(
    _ data: Data, descriptor: SettingDescriptorV1
) throws -> PreferenceStorageEnvelopeV1 {
        do {
            if descriptor.key == DeviceLocalReminderPolicyV1.key, data.count > 4_096 {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            let envelope = try CompatibilityCanonicalV1.decode(
                PreferenceStorageEnvelopeV1.self,
                from: data
            )
            guard envelope.schemaVersion == PreferenceStorageEnvelopeV1.schemaVersion,
                  envelope.writeRecord.map({
                    $0.operationID != SettingsValidationV1.zeroUUID
                        && CompatibilityCanonicalV1.validSHA256($0.canonicalValueDigest)
                        && $0.canonicalValueDigest
                            == CompatibilityCanonicalV1.sha256(envelope.canonicalValue)
                  }) ?? true,
                  envelope.migrationRecord.map({
                    CompatibilityCanonicalV1.validSHA256($0.requestDigest)
                        && CompatibilityCanonicalV1.validSHA256($0.legacySourceDigest)
                        && $0.receipt.operationID != SettingsValidationV1.zeroUUID
                        && $0.receipt.key == descriptor.key
                        && $0.receipt.migrationVersion == descriptor.migrationVersion
                        && CompatibilityCanonicalV1.validSHA256(
                            $0.receipt.canonicalValueDigest
                        )
                  }) ?? true else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            try descriptor.validateCanonicalValue(envelope.canonicalValue)
            if descriptor.key == DeviceLocalReminderPolicyV1.key {
                guard envelope.writeRecord == nil, envelope.migrationRecord == nil else {
                    throw PreferencesAdapterFailureV1.invalidCanonicalValue
                }
                let policy = try CompatibilityCanonicalV1.decode(DeviceLocalReminderPolicyV1.self,
                                                                  from: envelope.canonicalValue)
                try policy.validate()
                if let operation = envelope.reminderOperation {
                    try operation.validate()
                    guard operation.successor == policy else {
                        throw PreferencesAdapterFailureV1.invalidCanonicalValue
                    }
                } else {
                    guard policy.revision == 1, !policy.isEnabled, policy.detail == .generic else {
                        throw PreferencesAdapterFailureV1.invalidCanonicalValue
                    }
                }
            } else if envelope.reminderOperation != nil {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            return envelope
        } catch let error as PreferencesAdapterFailureV1 {
            throw error
        } catch {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
}

// MARK: - Closed cold Erase rating candidates (same sole codec and CAS)

/// Only this adapter file can issue an absent lookup after its real locked
/// configured-domain read and the matching lookup-mode post-read reproof.
fileprivate enum ColdEraseRatingAbsentDomainV1 { case missing, empty }
private enum ColdEraseRatingRawDomainV1 {
    case absent(ColdEraseRatingAbsentDomainV1)
    case cooldown(Data)
}

@MainActor final class ColdEraseRatingAbsentLookupV1 {
    private struct Storage {
        let acquisition: ColdEraseSchema2RatingObservationAcquisitionV1
        let adapter: PreferencesAdapterV1
        weak var plan: ColdEraseSchema2RatingPlanV1? = nil
        let runtimeOperationID: UUID
        let eraseID: UUID
        let persistentDomainName: String
        let actualDomain: ColdEraseRatingAbsentDomainV1
        var uncertainPlan: ColdEraseSchema2RatingPlanV1? = nil
        var permanentUncertainRetention: ColdEraseRatingAbsentLookupV1? = nil
    }
    private var storage: Storage
    // Actual stored-value operands only. Raw payload/string/typed backing,
    // weak runtime bookkeeping, object headers and allocator/VM are separate.
    static func declaredBackingBytes() -> UInt64 {
        UInt64(MemoryLayout<Storage>.stride)
    }
    var acquisition: ColdEraseSchema2RatingObservationAcquisitionV1 {
        get { storage.acquisition }
    }
    private var adapter: PreferencesAdapterV1 {
        get { storage.adapter }
    }
    private var plan: ColdEraseSchema2RatingPlanV1? {
        get { storage.plan }
        set { storage.plan = newValue }
    }
    private var runtimeOperationID: UUID {
        get { storage.runtimeOperationID }
    }
    private var eraseID: UUID {
        get { storage.eraseID }
    }
    private var persistentDomainName: String {
        get { storage.persistentDomainName }
    }
    private var actualDomain: ColdEraseRatingAbsentDomainV1 {
        get { storage.actualDomain }
    }
    private var uncertainPlan: ColdEraseSchema2RatingPlanV1? {
        get { storage.uncertainPlan }
        set { storage.uncertainPlan = newValue }
    }
    private var permanentUncertainRetention: ColdEraseRatingAbsentLookupV1? {
        get { storage.permanentUncertainRetention }
        set { storage.permanentUncertainRetention = newValue }
    }

    fileprivate init(adapter: PreferencesAdapterV1, plan: ColdEraseSchema2RatingPlanV1,
        acquisition: ColdEraseSchema2RatingObservationAcquisitionV1, actualDomain: ColdEraseRatingAbsentDomainV1) {
        storage = Storage(acquisition: acquisition, adapter: adapter, plan: plan,
            runtimeOperationID: plan.operationID, eraseID: plan.eraseID,
            persistentDomainName: plan.persistentDomainName, actualDomain: actualDomain)
    }

    /// Memory-only private-issuer association, never nil/Bool effect authority.
    func requireAdapterIssuedAssociation(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        guard self.adapter === adapter, self.plan === plan, uncertainPlan == nil,
              permanentUncertainRetention == nil, plan.operationID == runtimeOperationID,
              plan.eraseID == eraseID, plan.persistentDomainName == persistentDomainName else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        try acquisition.requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
        guard acquisition.mode == .lookup else { throw RatingEligibilityFailureV1.divergentReplay }
        switch actualDomain { case .missing, .empty: break }
    }

    fileprivate func poison() {
        permanentUncertainRetention = self
        if let plan {
            uncertainPlan = plan
            acquisition.poisonOnUncertainAcquisition(plan: plan, adapter: adapter)
            plan.poisonCandidateEncoding(adapter: adapter)
        }
    }
}

/// Observation DATA has no reconstructed CAS history. Main retains its actual
/// charged backing before the post-read owner reproof can throw.
@MainActor final class ColdEraseRatingExistingCooldownV1 {
    private enum Phase: Equatable { case observed, retired, uncertain }
    private struct Storage {
        let acquisition: ColdEraseSchema2RatingObservationAcquisitionV1
        let operationID: UUID
        let state: RatingRequestAttemptLedgerStateV1
        let erasedAt: Date
        let suppressUntil: Date
        let canonicalByteCount: UInt64
        let canonicalSHA256: String
        let adapter: PreferencesAdapterV1
        weak var plan: ColdEraseSchema2RatingPlanV1? = nil
        let runtimeOperationID: UUID
        let persistentDomainName: String
        let observationMode: ColdEraseRatingObservationModeV1
        var ratingRecipeBorrowActiveV4 = false
        var phase: Phase = .observed
        var uncertainPlan: ColdEraseSchema2RatingPlanV1? = nil
        var permanentUncertainRetention: ColdEraseRatingExistingCooldownV1? = nil
    }
    private var storage: Storage
    private var canonicalBacking: Data?
    // Actual stored-value operands only. Raw payload/string/typed backing,
    // weak runtime bookkeeping, object headers and allocator/VM are separate.
    static func declaredBackingBytes() -> UInt64 {
        UInt64(MemoryLayout<Storage>.stride) + UInt64(MemoryLayout<Data?>.stride)
    }
    var acquisition: ColdEraseSchema2RatingObservationAcquisitionV1 {
        get { storage.acquisition }
    }
    var operationID: UUID {
        get { storage.operationID }
    }
    var state: RatingRequestAttemptLedgerStateV1 {
        get { storage.state }
    }
    var erasedAt: Date {
        get { storage.erasedAt }
    }
    var suppressUntil: Date {
        get { storage.suppressUntil }
    }
    var canonicalByteCount: UInt64 {
        get { storage.canonicalByteCount }
    }
    var canonicalSHA256: String {
        get { storage.canonicalSHA256 }
    }
    private var adapter: PreferencesAdapterV1 {
        get { storage.adapter }
    }
    private var plan: ColdEraseSchema2RatingPlanV1? {
        get { storage.plan }
        set { storage.plan = newValue }
    }
    private var runtimeOperationID: UUID {
        get { storage.runtimeOperationID }
    }
    private var persistentDomainName: String {
        get { storage.persistentDomainName }
    }
    private var observationMode: ColdEraseRatingObservationModeV1 {
        get { storage.observationMode }
    }
    private var phase: Phase {
        get { storage.phase }
        set { storage.phase = newValue }
    }
    private var uncertainPlan: ColdEraseSchema2RatingPlanV1? {
        get { storage.uncertainPlan }
        set { storage.uncertainPlan = newValue }
    }
    private var permanentUncertainRetention: ColdEraseRatingExistingCooldownV1? {
        get { storage.permanentUncertainRetention }
        set { storage.permanentUncertainRetention = newValue }
    }

    fileprivate init(adapter: PreferencesAdapterV1, plan: ColdEraseSchema2RatingPlanV1,
        acquisition: ColdEraseSchema2RatingObservationAcquisitionV1, state: RatingRequestAttemptLedgerStateV1,
        erasedAt: Date, suppressUntil: Date, canonicalBytes: Data) {
        let observationMode = acquisition.mode
        let runtimeOperationID = plan.operationID, operationID = plan.eraseID
        let persistentDomainName = plan.persistentDomainName
        canonicalBacking = canonicalBytes
        let canonicalByteCount = UInt64(canonicalBytes.count)
        let canonicalSHA256 = CompatibilityCanonicalV1.sha256(canonicalBytes)
        storage = Storage(acquisition: acquisition, operationID: operationID,
            state: state, erasedAt: erasedAt, suppressUntil: suppressUntil,
            canonicalByteCount: canonicalByteCount, canonicalSHA256: canonicalSHA256,
            adapter: adapter, plan: plan, runtimeOperationID: runtimeOperationID,
            persistentDomainName: persistentDomainName, observationMode: observationMode)
    }

    private func requireIdentity(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        guard self.adapter === adapter, self.plan === plan,
              plan.operationID == runtimeOperationID, plan.eraseID == operationID,
              plan.persistentDomainName == persistentDomainName else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        try acquisition.requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
    }

    /// Memory-only, acyclic consumer for the actual Main plan. No IO or callback.
    func requireAdapterIssuedAssociation(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        try requireIdentity(plan: plan, adapter: adapter)
        guard phase == .observed, uncertainPlan == nil,
              let canonicalBacking, UInt64(canonicalBacking.count) == canonicalByteCount,
              canonicalByteCount > 0,
              canonicalByteCount <= PreferencesAdapterV1.coldEraseRatingCanonicalByteLimit else {
            throw RatingEligibilityFailureV1.staleState
        }
    }

    func requireBound(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        do {
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            guard try plan.requireObservationMode(adapter: adapter) == observationMode else {
                throw RatingEligibilityFailureV1.staleState
            }
        } catch { poison(); throw error }
    }

    /// Both actual private backings are compared without exporting either Data.
    func requireSameCanonicalCandidate(_ candidate: ColdEraseRatingCandidateV1,
        plan: ColdEraseSchema2RatingPlanV1, adapter: PreferencesAdapterV1) throws {
        do {
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            try candidate.requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            guard state == candidate.state, canonicalByteCount == candidate.canonicalByteCount,
                  canonicalSHA256 == candidate.canonicalSHA256, let canonicalBacking,
                  candidate.matchesCanonicalBacking(canonicalBacking) else {
                throw RatingEligibilityFailureV1.divergentReplay
            }
        } catch { poison(); candidate.poison(); throw error }
    }

    func retireCanonicalBacking(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        do {
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            guard !storage.ratingRecipeBorrowActiveV4 else { throw RatingEligibilityFailureV1.staleState }
            try plan.requireExistingCooldownBackingRetirement(self, adapter: adapter)
            canonicalBacking = nil
            phase = .retired
            try plan.recordExistingCooldownBackingRetired(self, adapter: adapter)
        } catch { poison(); throw error }
    }

    func requireCanonicalBackingCleared(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        try requireIdentity(plan: plan, adapter: adapter)
        guard phase == .retired, canonicalBacking == nil, !storage.ratingRecipeBorrowActiveV4, uncertainPlan == nil else {
            throw RatingEligibilityFailureV1.staleState
        }
    }

    fileprivate func poison() {
        phase = .uncertain
        permanentUncertainRetention = self
        if let plan {
            uncertainPlan = plan
            acquisition.poisonOnUncertainAcquisition(plan: plan, adapter: adapter)
            plan.poisonExistingCooldownObservation(self, adapter: adapter)
        }
    }
}

/// A recipe receipt is planned committed DATA, distinct from the actual return
/// of the one entered CAS. Only the adapter can issue this actual raw owner.
@MainActor final class ColdEraseRatingCandidateV1 {
    private enum Phase: Equatable { case prepared, enteredCAS, casReturned, checked, retired, uncertain }
    private struct Storage {
        let restorationAcquisition: ColdEraseSchema2RatingRestorationAcquisitionV1?
        let operationID: UUID
        let state: RatingRequestAttemptLedgerStateV1
        let persistedReceipt: RatingLedgerPersistenceReceiptV1
        let erasedAt: Date
        let suppressUntil: Date
        let canonicalByteCount: UInt64
        let canonicalSHA256: String
        let adapter: PreferencesAdapterV1
        weak var plan: ColdEraseSchema2RatingPlanV1? = nil
        let runtimeOperationID: UUID
        let persistentDomainName: String
        var phase: Phase = .prepared
        var actualCASReturn: RatingLedgerPersistenceReceiptV1? = nil
        var rawPointerActive: Bool = false
        var uncertainPlan: ColdEraseSchema2RatingPlanV1? = nil
        var permanentUncertainRetention: ColdEraseRatingCandidateV1? = nil
    }
    private var storage: Storage
    private var canonicalBacking: Data?
    // Actual stored-value operands only. Raw payload/string/typed backing,
    // weak runtime bookkeeping, object headers and allocator/VM are separate.
    static func declaredBackingBytes() -> UInt64 {
        UInt64(MemoryLayout<Storage>.stride) + UInt64(MemoryLayout<Data?>.stride)
    }
    var restorationAcquisition: ColdEraseSchema2RatingRestorationAcquisitionV1? {
        get { storage.restorationAcquisition }
    }
    var operationID: UUID {
        get { storage.operationID }
    }
    var state: RatingRequestAttemptLedgerStateV1 {
        get { storage.state }
    }
    var persistedReceipt: RatingLedgerPersistenceReceiptV1 {
        get { storage.persistedReceipt }
    }
    var erasedAt: Date {
        get { storage.erasedAt }
    }
    var suppressUntil: Date {
        get { storage.suppressUntil }
    }
    var canonicalByteCount: UInt64 {
        get { storage.canonicalByteCount }
    }
    var canonicalSHA256: String {
        get { storage.canonicalSHA256 }
    }
    private var adapter: PreferencesAdapterV1 {
        get { storage.adapter }
    }
    private var plan: ColdEraseSchema2RatingPlanV1? {
        get { storage.plan }
        set { storage.plan = newValue }
    }
    private var runtimeOperationID: UUID {
        get { storage.runtimeOperationID }
    }
    private var persistentDomainName: String {
        get { storage.persistentDomainName }
    }
    private var phase: Phase {
        get { storage.phase }
        set { storage.phase = newValue }
    }
    private var actualCASReturn: RatingLedgerPersistenceReceiptV1? {
        get { storage.actualCASReturn }
        set { storage.actualCASReturn = newValue }
    }
    private var rawPointerActive: Bool {
        get { storage.rawPointerActive }
        set { storage.rawPointerActive = newValue }
    }
    private var uncertainPlan: ColdEraseSchema2RatingPlanV1? {
        get { storage.uncertainPlan }
        set { storage.uncertainPlan = newValue }
    }
    private var permanentUncertainRetention: ColdEraseRatingCandidateV1? {
        get { storage.permanentUncertainRetention }
        set { storage.permanentUncertainRetention = newValue }
    }

    fileprivate init(adapter: PreferencesAdapterV1, plan: ColdEraseSchema2RatingPlanV1,
        restorationAcquisition: ColdEraseSchema2RatingRestorationAcquisitionV1?,
        state: RatingRequestAttemptLedgerStateV1, receipt: RatingLedgerPersistenceReceiptV1,
        erasedAt: Date, suppressUntil: Date, canonicalBytes: Data) {
        let runtimeOperationID = plan.operationID, operationID = plan.eraseID
        let persistentDomainName = plan.persistentDomainName
        canonicalBacking = canonicalBytes
        let canonicalByteCount = UInt64(canonicalBytes.count)
        let canonicalSHA256 = CompatibilityCanonicalV1.sha256(canonicalBytes)
        storage = Storage(restorationAcquisition: restorationAcquisition,
            operationID: operationID, state: state, persistedReceipt: receipt,
            erasedAt: erasedAt, suppressUntil: suppressUntil,
            canonicalByteCount: canonicalByteCount, canonicalSHA256: canonicalSHA256,
            adapter: adapter, plan: plan, runtimeOperationID: runtimeOperationID,
            persistentDomainName: persistentDomainName)
    }

    private func requireIdentity(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        guard self.adapter === adapter, self.plan === plan,
              plan.operationID == runtimeOperationID, plan.eraseID == operationID,
              plan.persistentDomainName == persistentDomainName else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        if let restorationAcquisition {
            try restorationAcquisition.requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            guard restorationAcquisition.byteCount == canonicalByteCount,
                  restorationAcquisition.sha256 == canonicalSHA256,
                  restorationAcquisition.chosenState == state else {
                throw RatingEligibilityFailureV1.divergentReplay
            }
        }
    }

    /// Main invokes this without reentering requireBound. No IO or Main call.
    func requireAdapterIssuedAssociation(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        try requireIdentity(plan: plan, adapter: adapter)
        guard phase != .retired, phase != .uncertain, uncertainPlan == nil,
              let canonicalBacking, UInt64(canonicalBacking.count) == canonicalByteCount,
              canonicalByteCount > 0,
              canonicalByteCount <= PreferencesAdapterV1.coldEraseRatingCanonicalByteLimit else {
            throw RatingEligibilityFailureV1.staleState
        }
    }

    func requireBound(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        do {
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            try plan.requireCandidate(self, adapter: adapter)
        } catch { poison(); throw error }
    }

    /// The synchronous Void-only pointer is borrowed solely within this call.
    /// Main's actual range consumer must neither retain it nor clone a recipe map.
    func withCanonicalBytes(plan: ColdEraseSchema2RatingPlanV1,
        _ body: (UnsafeRawBufferPointer) throws -> Void) throws {
        do {
            try requireBound(plan: plan, adapter: adapter)
            try plan.requireCandidateBytes(self, adapter: adapter)
            guard phase == .prepared, !rawPointerActive, canonicalBacking != nil else {
                throw RatingEligibilityFailureV1.staleState
            }
            rawPointerActive = true
            do {
                // Retirement refuses while this synchronous borrow is active.
                try canonicalBacking!.withUnsafeBytes(body)
            } catch {
                rawPointerActive = false
                throw error
            }
            rawPointerActive = false
            try requireBound(plan: plan, adapter: adapter)
        } catch { poison(); throw error }
    }

    fileprivate func matchesCanonicalBacking(_ bytes: Data) -> Bool {
        guard phase != .uncertain, phase != .retired, let canonicalBacking else { return false }
        return canonicalBacking == bytes
    }

    fileprivate func enterCAS(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
        guard phase == .prepared, !rawPointerActive, actualCASReturn == nil else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        phase = .enteredCAS
    }

    /// No throwing owner callback can run before this actual return is stored.
    fileprivate func captureActualCASReturn(_ receipt: RatingLedgerPersistenceReceiptV1) {
        actualCASReturn = receipt
        if phase == .enteredCAS { phase = .casReturned }
    }

    func requireActualCASReturn(_ receipt: RatingLedgerPersistenceReceiptV1,
        plan: ColdEraseSchema2RatingPlanV1, adapter: PreferencesAdapterV1) throws {
        try requireIdentity(plan: plan, adapter: adapter)
        guard (phase == .casReturned || phase == .checked), uncertainPlan == nil,
              actualCASReturn == receipt else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
    }

    fileprivate func markChecked() throws {
        guard phase == .casReturned, !rawPointerActive, actualCASReturn != nil else {
            throw RatingEligibilityFailureV1.staleState
        }
        phase = .checked
    }

    func retireCanonicalBacking(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        do {
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            guard phase == .checked, !rawPointerActive else {
                throw RatingEligibilityFailureV1.staleState
            }
            try plan.requireCanonicalBackingRetirement(candidate: self, adapter: adapter)
            canonicalBacking = nil
            phase = .retired
            try plan.recordCanonicalBackingRetired(candidate: self, adapter: adapter)
        } catch { poison(); throw error }
    }

    func requireCanonicalBackingCleared(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        try requireIdentity(plan: plan, adapter: adapter)
        guard phase == .retired, canonicalBacking == nil, !rawPointerActive,
              uncertainPlan == nil else {
            throw RatingEligibilityFailureV1.staleState
        }
    }

    fileprivate func poison() {
        phase = .uncertain
        permanentUncertainRetention = self
        if let plan {
            uncertainPlan = plan
            restorationAcquisition?.poisonOnUncertainAcquisition(plan: plan, adapter: adapter)
            plan.poisonCandidateCASAttempt(candidate: self, adapter: adapter)
        }
    }
}

/// A physical checked readback retains the real CAS return, including replay.
/// It owns no second canonical Data buffer and reconstructs no CAS history.
@MainActor final class ColdEraseRatingCheckedReceiptV1 {
    private struct Storage {
        let actualCASReceipt: RatingLedgerPersistenceReceiptV1
        let state: RatingRequestAttemptLedgerStateV1
        let erasedAt: Date
        let suppressUntil: Date
        let canonicalByteCount: UInt64
        let canonicalSHA256: String
        let adapter: PreferencesAdapterV1
        weak var plan: ColdEraseSchema2RatingPlanV1? = nil
        let candidate: ColdEraseRatingCandidateV1
    }
    private var storage: Storage
    // Actual stored-value operands only. Raw payload/string/typed backing,
    // weak runtime bookkeeping, object headers and allocator/VM are separate.
    static func declaredBackingBytes() -> UInt64 {
        UInt64(MemoryLayout<Storage>.stride)
    }
    var actualCASReceipt: RatingLedgerPersistenceReceiptV1 {
        get { storage.actualCASReceipt }
    }
    var state: RatingRequestAttemptLedgerStateV1 {
        get { storage.state }
    }
    var erasedAt: Date {
        get { storage.erasedAt }
    }
    var suppressUntil: Date {
        get { storage.suppressUntil }
    }
    var canonicalByteCount: UInt64 {
        get { storage.canonicalByteCount }
    }
    var canonicalSHA256: String {
        get { storage.canonicalSHA256 }
    }
    private var adapter: PreferencesAdapterV1 {
        get { storage.adapter }
    }
    private var plan: ColdEraseSchema2RatingPlanV1? {
        get { storage.plan }
        set { storage.plan = newValue }
    }
    private var candidate: ColdEraseRatingCandidateV1 {
        get { storage.candidate }
    }

    fileprivate init(adapter: PreferencesAdapterV1, plan: ColdEraseSchema2RatingPlanV1,
        candidate: ColdEraseRatingCandidateV1, actualReceipt: RatingLedgerPersistenceReceiptV1) {
        storage = Storage(actualCASReceipt: actualReceipt, state: candidate.state,
            erasedAt: candidate.erasedAt, suppressUntil: candidate.suppressUntil,
            canonicalByteCount: candidate.canonicalByteCount, canonicalSHA256: candidate.canonicalSHA256,
            adapter: adapter, plan: plan, candidate: candidate)
    }

    func requireAdapterIssuedAssociation(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1) throws {
        guard self.adapter === adapter, self.plan === plan,
              state == candidate.state, canonicalByteCount == candidate.canonicalByteCount,
              canonicalSHA256 == candidate.canonicalSHA256 else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        try candidate.requireActualCASReturn(actualCASReceipt, plan: plan, adapter: adapter)
    }

    func requireBound(plan: ColdEraseSchema2RatingPlanV1,
        candidate: ColdEraseRatingCandidateV1, adapter: PreferencesAdapterV1) throws {
        do {
            guard self.candidate === candidate else { throw RatingEligibilityFailureV1.divergentReplay }
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            try candidate.requireBound(plan: plan, adapter: adapter)
        } catch { self.candidate.poison(); throw error }
    }
}

extension PreferencesAdapterV1 {
    static let coldEraseRatingCanonicalByteLimit: UInt64 = 65_536
    static let coldEraseRatingMaximumRawWindowBytes: UInt64 = 196_608

    @MainActor private func coldEraseRatingDates(
        _ state: RatingRequestAttemptLedgerStateV1
    ) throws -> (erasedAt: Date, suppressUntil: Date) {
        try validateRatingEligibilityState(state)
        guard state.schemaVersion == RatingRequestAttemptLedgerStateV1.schemaVersion,
              state.revision == 1, state.attempts.isEmpty,
              case .erasedCooldown(let erasedAt, let suppressUntil) = state.origin,
              state.clockHighWatermarkUTC == erasedAt,
              erasedAt.timeIntervalSinceReferenceDate.isFinite,
              suppressUntil.timeIntervalSinceReferenceDate.isFinite,
              suppressUntil == erasedAt.addingTimeInterval(RatingEligibilityPolicyV1.eraseCooldownSeconds) else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        return (erasedAt, suppressUntil)
    }

    @MainActor private func coldEraseRatingByteCount(_ bytes: Data) throws -> UInt64 {
        guard let count = UInt64(exactly: bytes.count), count > 0,
              count <= Self.coldEraseRatingCanonicalByteLimit else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        return count
    }

    /// Copies exactly one already charged raw window; no loader alias survives.
    @MainActor private func coldEraseRatingOwnedCopy(_ bytes: Data) throws -> Data {
        _ = try coldEraseRatingByteCount(bytes)
        return try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count == bytes.count else {
                throw RatingEligibilityFailureV1.invalidValue
            }
            return Data(bytes: base, count: raw.count)
        }
    }

    @MainActor private func coldEraseRatingEnvelope(_ bytes: Data,
        eraseID: UUID) throws -> RatingEligibilityStorageEnvelopeV1 {
        _ = try coldEraseRatingByteCount(bytes)
        guard eraseID != SettingsValidationV1.zeroUUID else { throw RatingEligibilityFailureV1.invalidValue }
        // This is the incumbent private envelope and sole canonical codec.
        let envelope = try CompatibilityCanonicalV1.decode(RatingEligibilityStorageEnvelopeV1.self, from: bytes)
        _ = try coldEraseRatingDates(envelope.state)
        let record = envelope.writeRecord
        guard envelope.schemaVersion == RatingEligibilityStorageEnvelopeV1.schemaVersion,
              record.operationID == eraseID,
              record.successorStateSHA256 == envelope.state.stateSHA256,
              record.receipt.operationID == eraseID, record.receipt.expectedRevision == nil,
              record.receipt.resultingRevision == 1,
              record.receipt.stateSHA256 == envelope.state.stateSHA256,
              record.receipt.disposition == .committed else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        return envelope
    }

    @MainActor private func coldEraseRatingRawLocked(domainName: String,
        eraseID: UUID) throws -> ColdEraseRatingRawDomainV1 {
        guard !domainName.isEmpty, eraseID != SettingsValidationV1.zeroUUID else {
            throw RatingEligibilityFailureV1.invalidValue
        }
        guard let domain = defaults.persistentDomain(forName: domainName) else { return .absent(.missing) }
        guard !domain.isEmpty else { return .absent(.empty) }
        guard Set(domain.keys) == Set([Self.ratingEligibilityStorageKey]),
              let bytes = domain[Self.ratingEligibilityStorageKey] as? Data else {
            throw RatingEligibilityFailureV1.storageUnavailable
        }
        _ = try coldEraseRatingByteCount(bytes)
        guard defaults.data(forKey: Self.ratingEligibilityStorageKey) == bytes else {
            throw RatingEligibilityFailureV1.storageUnavailable
        }
        return .cooldown(bytes)
    }

    @MainActor func observeColdCompletedEraseCooldown(plan: ColdEraseSchema2RatingPlanV1) throws
        -> ColdEraseRatingExistingCooldownV1? {
        var observation: ColdEraseRatingExistingCooldownV1?
        var absence: ColdEraseRatingAbsentLookupV1?
        var acquisition: ColdEraseSchema2RatingObservationAcquisitionV1?
        do {
            let actual = try plan.beginObservationAcquisition(adapter: self)
            acquisition = actual
            try actual.requireCurrentBinding(plan: plan, adapter: self)
            let mode = actual.mode
            let eraseID = plan.eraseID, domainName = plan.persistentDomainName
            guard plan.operationID != SettingsValidationV1.zeroUUID else { throw RatingEligibilityFailureV1.invalidValue }
            let read = try withRatingEligibilityLock { () throws
                -> (observation: ColdEraseRatingExistingCooldownV1?, absentDomain: ColdEraseRatingAbsentDomainV1?) in
                switch try coldEraseRatingRawLocked(domainName: domainName, eraseID: eraseID) {
                case .absent(let actualDomain):
                    guard mode == .lookup else { throw RatingEligibilityFailureV1.storageUnavailable }
                    return (nil, actualDomain)
                case .cooldown(let bytes):
                    let envelope = try coldEraseRatingEnvelope(bytes, eraseID: eraseID)
                    let dates = try coldEraseRatingDates(envelope.state)
                    let owned = try coldEraseRatingOwnedCopy(bytes)
                    return (ColdEraseRatingExistingCooldownV1(adapter: self, plan: plan, acquisition: actual,
                        state: envelope.state, erasedAt: dates.erasedAt, suppressUntil: dates.suppressUntil,
                        canonicalBytes: owned), nil)
                }
            }
            observation = read.observation
            if let observation { try plan.retainExistingCooldownObservation(observation, adapter: self) }
            try actual.requireCurrentBinding(plan: plan, adapter: self)
            if let observation {
                guard read.absentDomain == nil else { throw RatingEligibilityFailureV1.divergentReplay }
                try observation.requireBound(plan: plan, adapter: self)
                return observation
            }
            guard mode == .lookup, let actualDomain = read.absentDomain else {
                throw RatingEligibilityFailureV1.storageUnavailable
            }
            // Issued only after the real absent/empty read and post-mode reproof.
            let issued = ColdEraseRatingAbsentLookupV1(adapter: self, plan: plan, acquisition: actual, actualDomain: actualDomain)
            absence = issued
            try plan.recordAbsentRatingLookup(issued, adapter: self)
            return nil
        } catch {
            if let observation { observation.poison() }
            else if let absence { absence.poison() }
            else if let acquisition { acquisition.poisonOnUncertainAcquisition(plan: plan, adapter: self) }
            else { plan.poisonCandidateEncoding(adapter: self) }
            throw error
        }
    }

    @MainActor func makeColdCompletedEraseCandidate(plan: ColdEraseSchema2RatingPlanV1) throws
        -> ColdEraseRatingCandidateV1 {
        var candidate: ColdEraseRatingCandidateV1?
        do {
            // Genuine Main admission precharges the whole196608 window first.
            let state = try plan.requireCandidateEncoding(adapter: self)
            let dates = try coldEraseRatingDates(state)
            guard plan.operationID != SettingsValidationV1.zeroUUID,
                  plan.eraseID != SettingsValidationV1.zeroUUID, !plan.persistentDomainName.isEmpty else {
                throw RatingEligibilityFailureV1.invalidValue
            }
            let recipe = RatingLedgerPersistenceReceiptV1(operationID: plan.eraseID,
                expectedRevision: nil, resultingRevision: 1, stateSHA256: state.stateSHA256,
                disposition: .committed)
            let envelope = RatingEligibilityStorageEnvelopeV1(state: state,
                writeRecord: .init(operationID: plan.eraseID, successorStateSHA256: state.stateSHA256, receipt: recipe))
            let bytes = try CompatibilityCanonicalV1.encode(envelope)
            _ = try coldEraseRatingByteCount(bytes)
            let issued = ColdEraseRatingCandidateV1(adapter: self, plan: plan, restorationAcquisition: nil,
                state: state, receipt: recipe,
                erasedAt: dates.erasedAt, suppressUntil: dates.suppressUntil, canonicalBytes: bytes)
            candidate = issued
            try issued.requireBound(plan: plan, adapter: self)
            return issued
        } catch {
            if let candidate { candidate.poison() } else { plan.poisonCandidateEncoding(adapter: self) }
            throw error
        }
    }

    @MainActor func restoreColdCompletedEraseCandidate(plan: ColdEraseSchema2RatingPlanV1,
        canonicalBytes: Data) throws -> ColdEraseRatingCandidateV1 {
        var candidate: ColdEraseRatingCandidateV1?
        var acquisition: ColdEraseSchema2RatingRestorationAcquisitionV1?
        do {
            guard plan.operationID != SettingsValidationV1.zeroUUID,
                  plan.eraseID != SettingsValidationV1.zeroUUID, !plan.persistentDomainName.isEmpty else {
                throw RatingEligibilityFailureV1.invalidValue
            }
            let count = try coldEraseRatingByteCount(canonicalBytes)
            let digest = CompatibilityCanonicalV1.sha256(canonicalBytes)
            let actual = try plan.beginPendingCandidateRestoration(adapter: self, byteCount: count, sha256: digest)
            acquisition = actual
            try actual.requireCurrentBinding(plan: plan, adapter: self)
            guard actual.byteCount == count, actual.sha256 == digest else {
                throw RatingEligibilityFailureV1.divergentReplay
            }
            let chosen = actual.chosenState
            _ = try coldEraseRatingDates(chosen)
            let envelope = try coldEraseRatingEnvelope(canonicalBytes, eraseID: plan.eraseID)
            guard envelope.state == chosen else { throw RatingEligibilityFailureV1.divergentReplay }
            try actual.requireCurrentBinding(plan: plan, adapter: self)
            let dates = try coldEraseRatingDates(envelope.state)
            // All throwing decoder/state/owner reproofs precede the owned copy.
            // Once acquired, that backing is immediately placed in its carrier.
            let owned = try coldEraseRatingOwnedCopy(canonicalBytes)
            let issued = ColdEraseRatingCandidateV1(adapter: self, plan: plan, restorationAcquisition: actual,
                state: envelope.state,
                receipt: envelope.writeRecord.receipt, erasedAt: dates.erasedAt,
                suppressUntil: dates.suppressUntil, canonicalBytes: owned)
            candidate = issued
            try issued.requireBound(plan: plan, adapter: self)
            return issued
        } catch {
            if let candidate { candidate.poison() }
            else if let acquisition { acquisition.poisonOnUncertainAcquisition(plan: plan, adapter: self) }
            else { plan.poisonCandidateEncoding(adapter: self) }
            throw error
        }
    }

    @MainActor func applyColdCompletedEraseCandidate(plan: ColdEraseSchema2RatingPlanV1,
        candidate: ColdEraseRatingCandidateV1) async throws -> ColdEraseRatingCheckedReceiptV1 {
        do {
            try candidate.requireBound(plan: plan, adapter: self)
            try plan.requireCASAdmission(adapter: self, candidate: candidate)
            try plan.retainCandidateCASAttempt(candidate: candidate, adapter: self)
            try candidate.enterCAS(plan: plan, adapter: self)
            let actualReceipt = try await compareAndSwap(operationID: plan.eraseID,
                expectedRevision: nil, successor: candidate.state)
            candidate.captureActualCASReturn(actualReceipt)
            try plan.requireCASReturn(adapter: self, candidate: candidate, actualReceipt: actualReceipt)
            try candidate.requireActualCASReturn(actualReceipt, plan: plan, adapter: self)
            guard actualReceipt.operationID == candidate.operationID,
                  actualReceipt.expectedRevision == nil, actualReceipt.resultingRevision == 1,
                  actualReceipt.stateSHA256 == candidate.state.stateSHA256,
                  (actualReceipt.disposition == .committed || actualReceipt.disposition == .idempotentReplay) else {
                throw RatingEligibilityFailureV1.divergentReplay
            }
            let eraseID = plan.eraseID, domainName = plan.persistentDomainName
            try withRatingEligibilityLock {
                guard case .cooldown(let bytes) = try coldEraseRatingRawLocked(domainName: domainName, eraseID: eraseID),
                      candidate.matchesCanonicalBacking(bytes) else { throw RatingEligibilityFailureV1.storageUnavailable }
                let envelope = try coldEraseRatingEnvelope(bytes, eraseID: eraseID)
                guard envelope.state == candidate.state,
                      envelope.writeRecord.receipt == candidate.persistedReceipt else {
                    throw RatingEligibilityFailureV1.divergentReplay
                }
            }
            try candidate.markChecked()
            let checked = ColdEraseRatingCheckedReceiptV1(adapter: self, plan: plan,
                candidate: candidate, actualReceipt: actualReceipt)
            try plan.recordCheckedRatingReadback(checked, candidate: candidate, adapter: self)
            return checked
        } catch { candidate.poison(); throw error }
    }
}


// RATING_SAME_SERVICE_SOLE_PREFS_SOURCE_V4_BEGIN
@MainActor final class ColdEraseSchema2RatingPreferencesSourceV4 {
    fileprivate struct Storage {
        let service: EraseAllService
        let adapter: PreferencesAdapterV1
        let defaults: UserDefaults
        let domainName: String
        let owner: ColdEraseSchema2TerminalOwnerV1
        let operation: EraseColdPreparationOperationV1
        let control: ColdEraseSchema2PostNamespaceCurrentControlOwnerV4
        let chargedBytes: UInt64
        var preparation: PreparationAttempt?
        var receipt: PreparationReceipt?
        var failure: Error?
    }
    @MainActor fileprivate final class PreparationAttempt {
        enum Result { case returned(Bool), threw(Error) }
        struct Cells { weak var source: ColdEraseSchema2RatingPreferencesSourceV4?; var result: Result?; var receipt: PreparationReceipt? }
        var cells: Cells
        init(source: ColdEraseSchema2RatingPreferencesSourceV4) { cells = .init(source: source) }
    }
    @MainActor final class PreparationReceipt {
        enum AbsentDomainV4 { case missing, empty }
        enum Readback { case absent(AbsentDomainV4), exactCooldown(state: RatingRequestAttemptLedgerStateV1, byteCount: UInt64, sha256: String) }
        private struct Cells {
            weak var source: ColdEraseSchema2RatingPreferencesSourceV4?
            let attempt: PreparationAttempt
            let keptExisting: Bool
            let readback: Readback
        }
        private let cells: Cells
        var keptExisting: Bool { cells.keptExisting }
        var readback: Readback { cells.readback }
        fileprivate static var declaredBackingBytes: UInt64 { UInt64(MemoryLayout<Cells>.stride) }
        fileprivate init(source: ColdEraseSchema2RatingPreferencesSourceV4,
            attempt: PreparationAttempt, kept: Bool, readback: Readback) {
            cells = .init(source: source, attempt: attempt, keptExisting: kept, readback: readback)
        }
        func requireAssociation(source: ColdEraseSchema2RatingPreferencesSourceV4) throws {
            guard cells.source === source, source.storage.preparation === cells.attempt,
                  source.storage.receipt === self, cells.attempt.cells.receipt === self,
                  source.storage.failure == nil,
                  case .returned(let actual) = cells.attempt.cells.result, actual == keptExisting else {
                throw RatingEligibilityFailureV1.divergentReplay
            }
            switch (actual, readback) {
            case (false, .absent): break
            case (true, .exactCooldown(let state, let count, let sha)):
                try state.validate()
                guard count > 0, count <= PreferencesAdapterV1.coldEraseRatingCanonicalByteLimit,
                      state.schemaVersion == 1, state.revision == 1, state.attempts.isEmpty,
                      case .erasedCooldown(let erasedAt, let until) = state.origin,
                      erasedAt.timeIntervalSince1970.isFinite,
                      until.timeIntervalSince(erasedAt) == 365 * 86_400,
                      state.clockHighWatermarkUTC == erasedAt,
                      KernelCanonicalHashV1.validSHA256(sha) else { throw RatingEligibilityFailureV1.divergentReplay }
            default: throw RatingEligibilityFailureV1.divergentReplay
            }
        }
    }
    fileprivate var storage: Storage
    var adapter: PreferencesAdapterV1 { storage.adapter }
    var persistentDomainName: String { storage.domainName }
    var preparationReceiptV4: PreparationReceipt? { storage.receipt }
    static func declaredBackingBytes(domainUTF8Count: UInt64) throws -> UInt64 {
        try ColdEraseControlBinaryV1.adding(UInt64(MemoryLayout<Storage>.stride
            + MemoryLayout<PreparationAttempt.Cells>.stride), PreparationReceipt.declaredBackingBytes,
            PreferencesAdapterV1.coldRatingAdapterStoredBackingV4,
            domainUTF8Count, 128, 3 * 65_536)
        // The existing three raw-window ceiling is prepaid, not widened.
        // Dictionary/codec/allocator and VM admission remain separately due.
    }
    fileprivate init(service: EraseAllService, defaults: UserDefaults, domainName: String,
        owner: ColdEraseSchema2TerminalOwnerV1, operation: EraseColdPreparationOperationV1,
        control: ColdEraseSchema2PostNamespaceCurrentControlOwnerV4, charge: UInt64) {
        storage = .init(service: service, adapter: PreferencesAdapterV1(defaults: defaults),
            defaults: defaults, domainName: domainName, owner: owner, operation: operation,
            control: control, chargedBytes: charge)
    }
    func requireAssociation(service: EraseAllService, owner: ColdEraseSchema2TerminalOwnerV1,
        operation: EraseColdPreparationOperationV1,
        control: ColdEraseSchema2PostNamespaceCurrentControlOwnerV4) throws {
        guard storage.service === service, storage.owner === owner, storage.operation === operation,
              storage.control === control, storage.failure == nil,
              storage.chargedBytes == (try Self.declaredBackingBytes(domainUTF8Count: UInt64(persistentDomainName.utf8.count))),
              !persistentDomainName.isEmpty else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        try adapter.requireSameColdRatingDefaultsV4(storage.defaults)
        try service.requireColdRatingPreferencesConfigurationV4(source: self, owner: owner, operation: operation)
    }
    func requireSameServiceDefaultsV4(service: EraseAllService, defaults: UserDefaults,
        domainName: String) throws {
        guard storage.service === service, storage.defaults === defaults,
              persistentDomainName == domainName, storage.failure == nil else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        try adapter.requireSameColdRatingDefaultsV4(defaults)
    }
    func prepareWithDurableRequestV4(_ request: ColdEraseSchema2RatingRequestV4) throws -> PreparationReceipt {
        do {
            guard storage.preparation == nil, storage.receipt == nil else { throw RatingEligibilityFailureV1.staleState }
            try request.requireDefaultsPreparationAdmission(source: self)
            let attempt = PreparationAttempt(source: self)
            storage.preparation = attempt // entered real owner before incumbent wipe/callback
            let kept: Bool
            do {
                kept = try AppLockNotificationTransactionFenceV1.perform {
                    try storage.adapter.preparePreferencesForCompletedErase(operationID: request.eraseID,
                        persistentDomainName: persistentDomainName)
                }
                attempt.cells.result = .returned(kept) // actual return before readback/current proof
            } catch { attempt.cells.result = .threw(error); throw error }
            let readback = try adapter.coldRatingPreparedDomainReadbackV4(eraseID: request.eraseID,
                domainName: persistentDomainName, kept: kept)
            let receipt = PreparationReceipt(source: self, attempt: attempt, kept: kept, readback: readback)
            attempt.cells.receipt = receipt; storage.receipt = receipt // retain before fallible consumer
            try receipt.requireAssociation(source: self)
            try request.recordDefaultsPreparationReturn(source: self, receipt: receipt)
            return receipt
        } catch {
            if storage.failure == nil { storage.failure = error }
            request.poisonOnUncertainEffect(); throw error
        }
    }
}

extension PreferencesAdapterV1 {
    @MainActor fileprivate func requireSameColdRatingDefaultsV4(_ actual: UserDefaults) throws {
        guard defaults === actual else { throw RatingEligibilityFailureV1.divergentReplay }
    }
    private struct ColdRatingAdapterCellsV4 {
        let defaults: UserDefaults
        let reminderPolicyEditOwner: ReminderPolicyEditOwnerV1
        let reminderPolicyEditGate: AppAccessGateV1?
        weak var reminderPolicyEditControl: AppLockNotificationControlStoreV1?
        let reminderPolicyEditsRetired: Bool
    }
    fileprivate static var coldRatingAdapterStoredBackingV4: UInt64 {
        UInt64(MemoryLayout<ColdRatingAdapterCellsV4>.stride)
        // ReminderPolicyEditOwnerV1 has no stored cells; runtime object costs remain due.
    }
    @MainActor static func issueColdRatingPreferencesSourceV4(service: EraseAllService,
        owner: ColdEraseSchema2TerminalOwnerV1, operation: EraseColdPreparationOperationV1,
        control: ColdEraseSchema2PostNamespaceCurrentControlOwnerV4,
        _ retain: (ColdEraseSchema2RatingPreferencesSourceV4) throws -> Void) throws {
        try service.withColdRatingPreferencesConfigurationV4(owner: owner, operation: operation) { defaults, domain in
            let charge = try ColdEraseSchema2RatingPreferencesSourceV4.declaredBackingBytes(domainUTF8Count: UInt64(domain.utf8.count))
            try control.reserveRatingPreferencesBackingV4(owner: owner, operation: operation, bytes: charge)
            let source = ColdEraseSchema2RatingPreferencesSourceV4(service: service, defaults: defaults,
                domainName: domain, owner: owner, operation: operation, control: control, charge: charge)
            try retain(source) // caller retains SAME returned owner before postproof
            try source.requireAssociation(service: service, owner: owner, operation: operation, control: control)
        }
    }
    @MainActor fileprivate func coldRatingPreparedDomainReadbackV4(eraseID: UUID,
        domainName: String, kept: Bool) throws -> ColdEraseSchema2RatingPreferencesSourceV4.PreparationReceipt.Readback {
        try withRatingEligibilityLock {
            switch try coldEraseRatingRawLocked(domainName: domainName, eraseID: eraseID) {
            case .absent(let actual):
                guard !kept else { throw RatingEligibilityFailureV1.divergentReplay }
                // Exact DATA from the incumbent private raw-domain result;
                // no caller can issue this retained checked Receipt.
                switch actual { case .missing: return .absent(.missing); case .empty: return .absent(.empty) }
            case .cooldown(let bytes):
                guard kept else { throw RatingEligibilityFailureV1.divergentReplay }
                let envelope = try coldEraseRatingEnvelope(bytes, eraseID: eraseID)
                return .exactCooldown(state: envelope.state, byteCount: try coldEraseRatingByteCount(bytes),
                    sha256: CompatibilityCanonicalV1.sha256(bytes))
            }
        }
    }
}

extension ColdEraseRatingExistingCooldownV1 {
    /// Same immutable owned backing; no Data alias/copy escapes. Add the actual
    /// borrowing cell to this owner's Storage and declared prebirth profile.
    func withCanonicalRatingRecipeV4(plan: ColdEraseSchema2RatingPlanV1,
        adapter: PreferencesAdapterV1, _ body: (UnsafeRawBufferPointer) throws -> Void) throws {
        do {
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            guard !storage.ratingRecipeBorrowActiveV4, let bytes = canonicalBacking,
                  UInt64(bytes.count) == canonicalByteCount else { throw RatingEligibilityFailureV1.staleState }
            storage.ratingRecipeBorrowActiveV4 = true
            try bytes.withUnsafeBytes { try body($0) }
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            storage.ratingRecipeBorrowActiveV4 = false
        } catch { poison(); throw error }
        // A reached callback fault permanently retains the active loan.
    }
}

extension ColdEraseRatingCandidateV1 {
    func requireHistoricalCheckedReturnV4(_ receipt: RatingLedgerPersistenceReceiptV1,
        plan: ColdEraseSchema2RatingPlanV1, adapter: PreferencesAdapterV1) throws {
        try requireIdentity(plan: plan, adapter: adapter)
        guard phase == .checked || phase == .retired, actualCASReturn == receipt,
              !rawPointerActive, uncertainPlan == nil else { throw RatingEligibilityFailureV1.divergentReplay }
        if phase == .retired {
            guard canonicalBacking == nil else { throw RatingEligibilityFailureV1.staleState }
        }
    }
    /// Historical immutable recipe DATA after actual CAS/readback. This is a
    /// separate closed borrower; the incumbent prepared-only effect borrower
    /// and all CAS/retirement guards retain their exact meaning.
    func withHistoricalCanonicalRatingRecipeV4(request: ColdEraseSchema2RatingRequestV4,
        plan: ColdEraseSchema2RatingPlanV1, _ body: (UnsafeRawBufferPointer) throws -> Void) throws {
        do {
            try requireAdapterIssuedAssociation(plan: plan, adapter: adapter)
            try request.requireCanonicalRecipeBorrow(candidate: self, plan: plan)
            guard !rawPointerActive, let bytes = canonicalBacking else { throw RatingEligibilityFailureV1.staleState }
            rawPointerActive = true
            try bytes.withUnsafeBytes { try body($0) }
            try request.requireCanonicalRecipeBorrow(candidate: self, plan: plan)
            rawPointerActive = false
        } catch { poison(); throw error }
    }
}

extension ColdEraseRatingCheckedReceiptV1 {
    func requireHistoricalAdapterReadbackV4(plan: ColdEraseSchema2RatingPlanV1,
        candidate: ColdEraseRatingCandidateV1, adapter: PreferencesAdapterV1) throws {
        guard self.plan === plan, self.adapter === adapter, self.candidate === candidate,
              state == candidate.state, canonicalByteCount == candidate.canonicalByteCount,
              canonicalSHA256 == candidate.canonicalSHA256,
              erasedAt == candidate.erasedAt, suppressUntil == candidate.suppressUntil else {
            throw RatingEligibilityFailureV1.divergentReplay
        }
        try candidate.requireHistoricalCheckedReturnV4(actualCASReceipt, plan: plan, adapter: adapter)
        // Actual adapter-issued locked readback DATA survives checked backing
        // retirement. Incumbent live requireBound/CAS guards remain exact.
    }
}
// RATING_SAME_SERVICE_SOLE_PREFS_SOURCE_V4_END

// PREFS_TERMINAL_SAME_CHECKED_COOLDOWN_REENCODING_V4_BEGIN
/// A separately charged canonical source for K after the genuine Rating
/// candidate workspace has been retired. It never rearms that old borrower.
@MainActor final class ColdEraseSchema2TerminalRatingCanonicalWorkspaceV4 {
    private struct Cells {
        let completed: ColdEraseSchema2CompletedRatingReceiptV4
        let candidate: ColdEraseRatingCandidateV1
        let checked: ColdEraseRatingCheckedReceiptV1
        var initializationEntered = false
        var initialized = false
        var borrowing = false
        var retirementEntered = false
        var retirementReturned = false
        var bytes: Data?
        var failure: Error?
    }
    private var cells: Cells
    static var declaredBackingBytes: UInt64 {
        UInt64(MemoryLayout<Cells>.stride + MemoryLayout<Cells>.alignment - 1
            + MemoryLayout<RatingEligibilityStorageEnvelopeV1>.stride
            + MemoryLayout<RatingEligibilityWriteRecordV1>.stride
            + MemoryLayout<RatingRequestAttemptLedgerStateV1>.stride
            + 6 * MemoryLayout<Data>.stride + 4 * MemoryLayout<Date>.stride) + 65_536
        // Separate new workspace. The incumbent three-window196608 policy,
        // retired Candidate/Existing buffers and original recipes are exact.
        // Foundation/COW/allocator/VM admission remains separately DUE.
    }
    var byteCount: UInt64 { cells.checked.canonicalByteCount }
    var sha256: String { cells.checked.canonicalSHA256 }
    private init(completed: ColdEraseSchema2CompletedRatingReceiptV4,
        candidate: ColdEraseRatingCandidateV1, checked: ColdEraseRatingCheckedReceiptV1) {
        cells = .init(completed: completed, candidate: candidate, checked: checked)
    }
    /// Native retains the SAME object in its prepaid fixed cell before this
    /// synchronous callback or any encoder/proof. No actual codec runs here.
    static func withUninitialized(completed: ColdEraseSchema2CompletedRatingReceiptV4,
        _ body: (ColdEraseSchema2TerminalRatingCanonicalWorkspaceV4) throws -> Void) throws {
        try completed.withTerminalCanonicalRatingInputsV4 { candidate, checked in
            let actual = ColdEraseSchema2TerminalRatingCanonicalWorkspaceV4(
                completed: completed, candidate: candidate, checked: checked)
            try body(actual)
            try actual.requireUninitializedAssociation(completed: completed)
        }
    }
    private func requireUninitializedAssociation(completed: ColdEraseSchema2CompletedRatingReceiptV4) throws {
        guard cells.completed === completed, cells.failure == nil,
              !cells.initializationEntered, !cells.initialized, cells.bytes == nil,
              !cells.borrowing, !cells.retirementEntered else { throw RatingEligibilityFailureV1.staleState }
        try completed.requireTerminalCanonicalRatingInputsV4(candidate: cells.candidate, checked: cells.checked)
    }
    func initialize(completed: ColdEraseSchema2CompletedRatingReceiptV4) throws {
        do {
            try requireUninitializedAssociation(completed: completed)
            cells.initializationEntered = true // actual prospective codec entry retained before allocation
            let state = cells.checked.state
            guard state == cells.candidate.state, state.schemaVersion == RatingRequestAttemptLedgerStateV1.schemaVersion,
                  state.revision == 1, state.attempts.isEmpty,
                  case .erasedCooldown(let erasedAt, let suppressUntil) = state.origin,
                  state.clockHighWatermarkUTC == erasedAt,
                  erasedAt == cells.checked.erasedAt, erasedAt == cells.candidate.erasedAt,
                  suppressUntil == cells.checked.suppressUntil, suppressUntil == cells.candidate.suppressUntil,
                  erasedAt.timeIntervalSinceReferenceDate.isFinite,
                  suppressUntil.timeIntervalSinceReferenceDate.isFinite,
                  suppressUntil == erasedAt.addingTimeInterval(RatingEligibilityPolicyV1.eraseCooldownSeconds),
                  RatingEligibilityPolicyV1.eraseCooldownSeconds == 365 * 86_400,
                  cells.candidate.persistedReceipt.operationID == cells.candidate.operationID,
                  cells.candidate.persistedReceipt.expectedRevision == nil,
                  cells.candidate.persistedReceipt.resultingRevision == 1,
                  cells.candidate.persistedReceipt.stateSHA256 == state.stateSHA256,
                  byteCount > 0, byteCount <= 65_536 else { throw RatingEligibilityFailureV1.invalidValue }
            let envelope = RatingEligibilityStorageEnvelopeV1(state: state, writeRecord: .init(
                operationID: cells.candidate.operationID, successorStateSHA256: state.stateSHA256,
                receipt: cells.candidate.persistedReceipt))
            let actual = try CompatibilityCanonicalV1.encode(envelope)
            cells.bytes = actual // genuine returned raw owner before any fallible postproof
            guard UInt64(actual.count) == byteCount,
                  CompatibilityCanonicalV1.sha256(actual) == sha256,
                  try CompatibilityCanonicalV1.decode(RatingEligibilityStorageEnvelopeV1.self, from: actual) == envelope else {
                throw RatingEligibilityFailureV1.invalidValue
            }
            try completed.requireTerminalCanonicalRatingInputsV4(candidate: cells.candidate, checked: cells.checked)
            cells.initialized = true
        } catch { if cells.failure == nil { cells.failure = error }; throw error }
    }
    func requireHistoricalAssociation(completed: ColdEraseSchema2CompletedRatingReceiptV4) throws {
        guard cells.completed === completed, cells.failure == nil,
              cells.initializationEntered, cells.initialized,
              byteCount > 0, byteCount <= 65_536 else { throw RatingEligibilityFailureV1.staleState }
        if cells.retirementEntered {
            guard cells.retirementReturned, cells.bytes == nil, !cells.borrowing else { throw RatingEligibilityFailureV1.staleState }
        } else {
            guard !cells.retirementReturned, let actual = cells.bytes,
                  UInt64(actual.count) == byteCount else { throw RatingEligibilityFailureV1.staleState }
        }
        try completed.requireTerminalCanonicalRatingInputsV4(candidate: cells.candidate, checked: cells.checked)
        // Pure genuine retained Rating result; never old canonical workspace,
        // current Control/Common, physical journal pin, Defaults, CAS or clock.
    }
    func withChunk(completed: ColdEraseSchema2CompletedRatingReceiptV4, offset: UInt64, count: Int,
        _ body: (UnsafeRawBufferPointer) throws -> Void) throws {
        do {
            try requireHistoricalAssociation(completed: completed)
            guard !cells.borrowing, count > 0, count <= 65_536, offset <= byteCount,
                  UInt64(count) <= byteCount - offset, let start = Int(exactly: offset),
                  !cells.retirementEntered, !cells.retirementReturned,
                  let bytes = cells.bytes else { throw RatingEligibilityFailureV1.staleState }
            cells.borrowing = true
            try bytes.withUnsafeBytes { try body(UnsafeRawBufferPointer(rebasing: $0[start..<start + count])) }
            try requireHistoricalAssociation(completed: completed); cells.borrowing = false
        } catch { if cells.failure == nil { cells.failure = error }; throw error }
    }
}
// PREFS_TERMINAL_SAME_CHECKED_COOLDOWN_REENCODING_V4_END
// PREFS_TERMINAL_POSITIVE_CANONICAL_REFERENCE_RETIREMENT_V4_BEGIN
extension ColdEraseSchema2TerminalRatingCanonicalWorkspaceV4 {
    func retireAfterActualTerminalPublicationV4(publication: ColdEraseSchema2TerminalPublicationReceiptV4,
        completed: ColdEraseSchema2CompletedRatingReceiptV4) throws {
        do {
            try requireHistoricalAssociation(completed: completed)
            try publication.requireConsumedRatingCanonicalWorkspaceV4(self, completed: completed)
            guard !cells.borrowing, !cells.retirementEntered, !cells.retirementReturned,
                  cells.bytes != nil else { throw RatingEligibilityFailureV1.staleState }
            cells.retirementEntered = true // one-way before sole private raw reference detaches
            cells.bytes = nil
            cells.retirementReturned = true // actual reference assignment returned
            try requireReturnedOwnedRawRetirementV4(completed: completed)
            try publication.requireConsumedRatingCanonicalWorkspaceV4(self, completed: completed)
        } catch { if cells.failure == nil { cells.failure = error }; throw error }
    }
    func requireReturnedOwnedRawRetirementV4(completed: ColdEraseSchema2CompletedRatingReceiptV4) throws {
        guard cells.retirementEntered, cells.retirementReturned, cells.bytes == nil,
              !cells.borrowing else { throw RatingEligibilityFailureV1.staleState }
        try requireHistoricalAssociation(completed: completed)
        // Checked envelope/count/SHA/date/CAS history remains real comparison
        // DATA. There is no borrower rearm, fresh clock or Defaults/CAS call.
        // Foundation/COW/VM and wider alias retirement remain separately DUE.
    }
}
// PREFS_TERMINAL_POSITIVE_CANONICAL_REFERENCE_RETIREMENT_V4_END


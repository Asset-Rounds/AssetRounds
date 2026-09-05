import Foundation

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

private struct PreferenceStorageEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let canonicalValue: Data
    let writeRecord: PreferenceWriteRecordV1?
    let migrationRecord: PreferenceMigrationRecordV1?

    init(
        canonicalValue: Data,
        writeRecord: PreferenceWriteRecordV1? = nil,
        migrationRecord: PreferenceMigrationRecordV1? = nil
    ) {
        schemaVersion = Self.schemaVersion
        self.canonicalValue = canonicalValue
        self.writeRecord = writeRecord
        self.migrationRecord = migrationRecord
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
    @unchecked Sendable {
    static let storagePrefix = "settings.v1."
    private static let ratingEligibilityStorageKey = "rating-eligibility.v1"
    private static let ratingEligibilityLock = NSLock()
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func readCanonicalValue(for descriptor: SettingDescriptorV1) throws -> Data {
        try withLock {
            try requireDeviceLocal(descriptor)
            guard let stored = defaults.data(forKey: storageKey(descriptor.key)) else {
                return descriptor.defaultCanonicalValue
            }
            return try decodeEnvelope(stored, descriptor: descriptor).canonicalValue
        }
    }

    func writeCanonicalValue(
        _ value: Data,
        descriptor: SettingDescriptorV1,
        operationID: UUID
    ) throws {
        try withLock {
            try requireDeviceLocal(descriptor)
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
            guard operationID != UUID.zero else {
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
            guard operationID != UUID.zero,
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
        do {
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
            try validate(envelope.canonicalValue, descriptor: descriptor)
            return envelope
        } catch let error as PreferencesAdapterFailureV1 {
            throw error
        } catch {
            throw PreferencesAdapterFailureV1.invalidCanonicalValue
        }
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
            guard envelope.writeRecord.operationID != UUID.zero,
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
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func withRatingEligibilityLock<T>(_ body: () throws -> T) throws -> T {
        Self.ratingEligibilityLock.lock()
        defer { Self.ratingEligibilityLock.unlock() }
        return try body()
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

// MARK: - V30 globalization presentation preference

extension PreferencesAdapterV1 {
    private static let globalizationFallbackKey = storagePrefix + "device.v30.globalization.fallback-diagnostic"

    /// Stores only the most recent fallback category, never language lists,
    /// customer text, keys, timestamps, or workspace identifiers.
    func recordGlobalizationFallback(_ value: EffectiveLanguageFallbackDiagnosticV1?) throws {
        try withLock {
            guard let value else {
                defaults.removeObject(forKey: Self.globalizationFallbackKey)
                return
            }
            guard value.usedEnglishFallback == (value.provenance == .englishFallback) else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            let bytes = try CompatibilityCanonicalV1.encode(value)
            guard bytes.count <= 256 else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            defaults.set(bytes, forKey: Self.globalizationFallbackKey)
        }
    }

    func readGlobalizationFallback() throws -> EffectiveLanguageFallbackDiagnosticV1? {
        try withLock {
            guard let bytes = defaults.data(forKey: Self.globalizationFallbackKey) else { return nil }
            guard bytes.count <= 256 else { throw PreferencesAdapterFailureV1.invalidCanonicalValue }
            let value = try CompatibilityCanonicalV1.decode(EffectiveLanguageFallbackDiagnosticV1.self, from: bytes)
            guard value.usedEnglishFallback == (value.provenance == .englishFallback) else {
                throw PreferencesAdapterFailureV1.invalidCanonicalValue
            }
            return value
        }
    }
}

extension PreferencesAdapterV1 {
    func readGlobalizationPresentationPreference() throws
        -> GlobalizationPresentationPreferenceV1 {
        let descriptor = try GlobalizationDevicePreferenceV1.descriptor()
        let value = try CompatibilityCanonicalV1.decode(
            GlobalizationPresentationPreferenceV1.self,
            from: readCanonicalValue(for: descriptor)
        )
        try value.validate()
        return value
    }

    func writeGlobalizationPresentationPreference(
        _ value: GlobalizationPresentationPreferenceV1,
        operationID: UUID
    ) throws {
        try value.validate()
        let descriptor = try GlobalizationDevicePreferenceV1.descriptor()
        try writeCanonicalValue(
            CompatibilityCanonicalV1.encode(value),
            descriptor: descriptor,
            operationID: operationID
        )
    }

    func migrateGlobalizationPresentationPreference(operationID: UUID) throws
        -> GlobalizationPresentationPreferenceV1 {
        let descriptor = try GlobalizationDevicePreferenceV1.descriptor()
        _ = try migrate(
            descriptor: descriptor,
            legacyKeys: GlobalizationDevicePreferenceV1.legacyKeys,
            operationID: operationID
        )
        return try readGlobalizationPresentationPreference()
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

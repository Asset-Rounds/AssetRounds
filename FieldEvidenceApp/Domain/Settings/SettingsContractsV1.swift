import Foundation

enum SettingsContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDescriptor
    case duplicateKey
    case unknownKey
    case invalidMigration
    case scopeMismatch
    case staleRevision
    case changedOperation
}

enum SettingValueKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case boolean = "BOOLEAN"
    case boundedString = "BOUNDED_STRING"
    case boundedStringSet = "BOUNDED_STRING_SET"
    case surveyDefinitionPreferenceReferenceSet = "SURVEY_DEFINITION_PREFERENCE_REFERENCE_SET"
    case recentInputMemory = "RECENT_INPUT_MEMORY"
}

enum SettingScopeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case deviceLocal = "DEVICE_LOCAL"
    case workspaceCanonical = "WORKSPACE_CANONICAL"
    case derived = "DERIVED"
}

enum PreferenceStorageDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case soleDevicePreferencesAdapter = "SOLE_DEVICE_PREFERENCES_ADAPTER"
    case workspaceWriter = "WORKSPACE_WRITER"
    case nonpersistentDerived = "NONPERSISTENT_DERIVED"
}

enum SettingBackupDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case excludedDeviceLocal = "EXCLUDED_DEVICE_LOCAL"
    case canonicalWorkspaceBackup = "CANONICAL_WORKSPACE_BACKUP"
    case notApplicable = "NOT_APPLICABLE"
}

enum SettingResetDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case restoreDefault = "RESTORE_DEFAULT"
    case preserveAcknowledgement = "PRESERVE_ACKNOWLEDGEMENT"
    case rebuild = "REBUILD"
}

enum SettingEraseDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case restoreDefault = "RESTORE_DEFAULT"
    case clearCanonical = "CLEAR_CANONICAL"
    case rebuild = "REBUILD"
}

enum SettingPrivacyDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case devicePreferenceNoCustomerData = "DEVICE_PREFERENCE_NO_CUSTOMER_DATA"
    case workspaceCanonical = "WORKSPACE_CANONICAL"
    case derivedNoPersistence = "DERIVED_NO_PERSISTENCE"
}

struct SettingDescriptorV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumValueBytes = 65_536

    let schemaVersion: Int
    let key: String
    let valueKind: SettingValueKindV1
    let scope: SettingScopeV1
    let storage: PreferenceStorageDispositionV1
    let defaultCanonicalValue: Data
    let maximumCanonicalBytes: Int
    let migrationVersion: Int
    let backup: SettingBackupDispositionV1
    let reset: SettingResetDispositionV1
    let erase: SettingEraseDispositionV1
    let privacy: SettingPrivacyDispositionV1
    let localizationKey: String
    let changesHistoricOutput: Bool

    init(
        key: String,
        valueKind: SettingValueKindV1,
        scope: SettingScopeV1,
        storage: PreferenceStorageDispositionV1,
        defaultCanonicalValue: Data,
        maximumCanonicalBytes: Int,
        migrationVersion: Int,
        backup: SettingBackupDispositionV1,
        reset: SettingResetDispositionV1,
        erase: SettingEraseDispositionV1,
        privacy: SettingPrivacyDispositionV1,
        localizationKey: String,
        changesHistoricOutput: Bool = false
    ) throws {
        schemaVersion = Self.schemaVersion
        self.key = key
        self.valueKind = valueKind
        self.scope = scope
        self.storage = storage
        self.defaultCanonicalValue = defaultCanonicalValue
        self.maximumCanonicalBytes = maximumCanonicalBytes
        self.migrationVersion = migrationVersion
        self.backup = backup
        self.reset = reset
        self.erase = erase
        self.privacy = privacy
        self.localizationKey = localizationKey
        self.changesHistoricOutput = changesHistoricOutput
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SettingsValidationV1.validToken(key, maximumBytes: 160),
              SettingsValidationV1.validToken(localizationKey, maximumBytes: 160),
              maximumCanonicalBytes > 0,
              maximumCanonicalBytes <= Self.maximumValueBytes,
              defaultCanonicalValue.count <= maximumCanonicalBytes,
              migrationVersion > 0 else {
            throw SettingsContractFailureV1.invalidDescriptor
        }
        do {
            try validateCanonicalValue(defaultCanonicalValue)
        } catch {
            throw SettingsContractFailureV1.invalidDescriptor
        }
        switch scope {
        case .deviceLocal:
            guard storage == .soleDevicePreferencesAdapter,
                  backup == .excludedDeviceLocal,
                  privacy == .devicePreferenceNoCustomerData,
                  !SurveySessionDevicePersistenceBoundaryV1.isCanonicalFactKey(key) else {
                throw SettingsContractFailureV1.scopeMismatch
            }
        case .workspaceCanonical:
            guard storage == .workspaceWriter,
                  backup == .canonicalWorkspaceBackup,
                  privacy == .workspaceCanonical else {
                throw SettingsContractFailureV1.scopeMismatch
            }
        case .derived:
            guard storage == .nonpersistentDerived,
                  backup == .notApplicable,
                  reset == .rebuild,
                  erase == .rebuild,
                  privacy == .derivedNoPersistence else {
                throw SettingsContractFailureV1.scopeMismatch
            }
        }
    }

    func validateCanonicalValue(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumCanonicalBytes else {
            throw SettingsContractFailureV1.invalidValue
        }
        switch valueKind {
        case .boolean:
            _ = try CompatibilityCanonicalV1.decode(Bool.self, from: data)
        case .boundedString:
            let value = try CompatibilityCanonicalV1.decode(String.self, from: data)
            guard SettingsValidationV1.validToken(value, maximumBytes: maximumCanonicalBytes) else {
                throw SettingsContractFailureV1.invalidValue
            }
        case .boundedStringSet:
            let value = try CompatibilityCanonicalV1.decode([String].self, from: data)
            guard value == value.sorted(),
                  Set(value).count == value.count,
                  value.allSatisfy({ SettingsValidationV1.validToken($0, maximumBytes: 200) }) else {
                throw SettingsContractFailureV1.invalidValue
            }
        case .surveyDefinitionPreferenceReferenceSet:
            guard SurveyDefinitionDeviceMemoryV1.isPreferenceKey(key) else {
                throw SettingsContractFailureV1.invalidValue
            }
            let value = try CompatibilityCanonicalV1.decode(
                [SurveyDefinitionPreferenceReferenceV1].self,
                from: data
            )
            let canonical = try SurveyDefinitionDeviceMemoryV1.canonicalReferences(
                value,
                forKey: key
            )
            guard canonical == value else {
                throw SettingsContractFailureV1.invalidValue
            }
        case .recentInputMemory:
            let value = try CompatibilityCanonicalV1.decode(RecentInputMemoryV1.self, from: data)
            try value.validate()
        }
    }

    func lifecycleDisposition(
        for operation: SettingsLifecycleOperationV1
    ) -> SettingLifecycleDispositionV1 {
        switch operation {
        case .backup, .restore, .clone, .fork, .importData, .export, .report, .search:
            switch scope {
            case .deviceLocal: return .excluded
            case .workspaceCanonical: return .workspaceCanonicalIncluded
            case .derived: return .rebuildDerived
            }
        case .reset:
            switch reset {
            case .restoreDefault: return .restoreDefault
            case .preserveAcknowledgement: return .preserveCanonical
            case .rebuild: return .rebuildDerived
            }
        case .delete, .erase:
            switch erase {
            case .restoreDefault: return .restoreDefault
            case .clearCanonical: return .clearCanonical
            case .rebuild: return .rebuildDerived
            }
        case .rebuild:
            return scope == .derived ? .rebuildDerived : .preserveCanonical
        case .migration, .replay, .retention, .interruptionRecovery:
            switch scope {
            case .deviceLocal: return .deviceLocalOnly
            case .workspaceCanonical: return .workspaceCanonicalIncluded
            case .derived: return .rebuildDerived
            }
        case .compatibility, .downgrade, .forwardFix:
            return changesHistoricOutput ? .failClosed : .preserveCanonical
        }
    }
}

struct WorkspaceSettingRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: UUID
    let key: String
    let canonicalValue: Data
    let revision: UInt64
    let mutationID: UUID

    init(
        workspaceID: UUID,
        key: String,
        canonicalValue: Data,
        revision: UInt64,
        mutationID: UUID
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.key = key
        self.canonicalValue = canonicalValue
        self.revision = revision
        self.mutationID = mutationID
        guard workspaceID != SettingsValidationV1.zeroUUID,
              mutationID != SettingsValidationV1.zeroUUID,
              SettingsValidationV1.validToken(key, maximumBytes: 160),
              !canonicalValue.isEmpty,
              canonicalValue.count <= SettingDescriptorV1.maximumValueBytes else {
            throw SettingsContractFailureV1.invalidValue
        }
    }
}

enum SettingsMigrationDispositionV1: String, Codable, Sendable {
    case initializedFromAbsence = "INITIALIZED_FROM_ABSENCE"
    case migratedLegacyValue = "MIGRATED_LEGACY_VALUE"
    case adoptedCurrentValue = "ADOPTED_CURRENT_VALUE"
    case replacedInvalidLegacyWithDefault = "REPLACED_INVALID_LEGACY_WITH_DEFAULT"
}

struct SettingsMigrationReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let key: String
    let migrationVersion: Int
    let disposition: SettingsMigrationDispositionV1
    let canonicalValueDigest: String

    init(
        operationID: UUID,
        key: String,
        migrationVersion: Int,
        disposition: SettingsMigrationDispositionV1,
        canonicalValueDigest: String
    ) throws {
        self.operationID = operationID
        self.key = key
        self.migrationVersion = migrationVersion
        self.disposition = disposition
        self.canonicalValueDigest = canonicalValueDigest
        guard operationID != SettingsValidationV1.zeroUUID,
              SettingsValidationV1.validToken(key, maximumBytes: 160),
              migrationVersion > 0,
              CompatibilityCanonicalV1.validSHA256(canonicalValueDigest) else {
            throw SettingsContractFailureV1.invalidMigration
        }
    }

    private enum CodingKeys: String, CodingKey {
        case operationID
        case key
        case migrationVersion
        case disposition
        case canonicalValueDigest
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            operationID: container.decode(UUID.self, forKey: .operationID),
            key: container.decode(String.self, forKey: .key),
            migrationVersion: container.decode(Int.self, forKey: .migrationVersion),
            disposition: container.decode(
                SettingsMigrationDispositionV1.self,
                forKey: .disposition
            ),
            canonicalValueDigest: container.decode(
                String.self,
                forKey: .canonicalValueDigest
            )
        )
    }
}

enum SettingsLifecycleOperationV1: String, CaseIterable, Codable, Sendable {
    case migration = "MIGRATION"
    case backup = "BACKUP"
    case restore = "RESTORE"
    case clone = "CLONE"
    case fork = "FORK"
    case importData = "IMPORT"
    case export = "EXPORT"
    case report = "REPORT"
    case search = "SEARCH"
    case reset = "RESET"
    case rebuild = "REBUILD"
    case replay = "REPLAY"
    case delete = "DELETE"
    case erase = "ERASE"
    case retention = "RETENTION"
    case compatibility = "COMPATIBILITY"
    case downgrade = "DOWNGRADE"
    case forwardFix = "FORWARD_FIX"
    case interruptionRecovery = "INTERRUPTION_RECOVERY"
}

enum SettingLifecycleDispositionV1: String, Codable, Sendable {
    case deviceLocalOnly = "DEVICE_LOCAL_ONLY"
    case workspaceCanonicalIncluded = "WORKSPACE_CANONICAL_INCLUDED"
    case excluded = "EXCLUDED"
    case rebuildDerived = "REBUILD_DERIVED"
    case restoreDefault = "RESTORE_DEFAULT"
    case preserveCanonical = "PRESERVE_CANONICAL"
    case clearCanonical = "CLEAR_CANONICAL"
    case failClosed = "FAIL_CLOSED"
}

struct SettingsLifecycleReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let operation: SettingsLifecycleOperationV1
    let affectedKeys: [String]
    let preservedWorkspaceCanonicalTruth: Bool

    init(
        operationID: UUID,
        operation: SettingsLifecycleOperationV1,
        affectedKeys: [String],
        preservedWorkspaceCanonicalTruth: Bool
    ) throws {
        self.operationID = operationID
        self.operation = operation
        self.affectedKeys = affectedKeys.sorted()
        self.preservedWorkspaceCanonicalTruth = preservedWorkspaceCanonicalTruth
        guard operationID != SettingsValidationV1.zeroUUID,
              self.affectedKeys.count == Set(self.affectedKeys).count,
              self.affectedKeys.allSatisfy({ SettingsValidationV1.validToken($0, maximumBytes: 160) }),
              ([.erase, .delete].contains(operation)) != preservedWorkspaceCanonicalTruth else {
            throw SettingsContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case operationID
        case operation
        case affectedKeys
        case preservedWorkspaceCanonicalTruth
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            operationID: container.decode(UUID.self, forKey: .operationID),
            operation: container.decode(SettingsLifecycleOperationV1.self, forKey: .operation),
            affectedKeys: container.decode([String].self, forKey: .affectedKeys),
            preservedWorkspaceCanonicalTruth: container.decode(
                Bool.self,
                forKey: .preservedWorkspaceCanonicalTruth
            )
        )
    }
}

struct HapticFeedbackPreferenceV1: Codable, Equatable, Sendable {
    static let key = "device.hapticFeedback"
    static let logicalDefault = HapticFeedbackPreferenceV1(isEnabled: true)
    let isEnabled: Bool

    init(isEnabled: Bool) { self.isEnabled = isEnabled }

    func effectiveEmission(runtimeAvailable: Bool, safeContext: Bool) -> Bool {
        isEnabled && runtimeAvailable && safeContext
    }
}

/// Device-local navigation preference only. Canonical saved-view definitions
/// remain WorkspaceWriter-owned V7 records, and raw query text is never stored
/// through this setting.
struct LastSelectedSmartViewPreferenceV1: Codable, Equatable, Sendable {
    static let key = "device.lastSelectedSmartViewID"
    static let logicalDefault = BuiltInSmartViewV1.recent.stableID
    let stableID: String

    init(stableID: String) throws {
        guard SearchContractValidationV1.validID(stableID) else {
            throw SettingsContractFailureV1.invalidValue
        }
        self.stableID = stableID
    }
}

enum SuggestionSourceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case reviewedRecentOption = "REVIEWED_RECENT_OPTION"
    case reviewedStableLocalReference = "REVIEWED_STABLE_LOCAL_REFERENCE"
}

enum SuggestedInputKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case optionID = "OPTION_ID"
    case stableLocalReference = "STABLE_LOCAL_REFERENCE"
}

enum SuggestedInputPrivacyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case referenceOnlyNoRawCustomerData = "REFERENCE_ONLY_NO_RAW_CUSTOMER_DATA"
}

struct SuggestedInputV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: UUID
    let semanticFieldID: String
    let kind: SuggestedInputKindV1
    let valueID: String
    let privacy: SuggestedInputPrivacyV1
    let source: SuggestionSourceV1
    let packageReleaseID: String
    let expectedRevision: UInt64
    let lastAcceptedAt: Date

    init(
        workspaceID: UUID,
        semanticFieldID: String,
        kind: SuggestedInputKindV1,
        valueID: String,
        privacy: SuggestedInputPrivacyV1 = .referenceOnlyNoRawCustomerData,
        source: SuggestionSourceV1,
        packageReleaseID: String,
        expectedRevision: UInt64,
        lastAcceptedAt: Date
    ) throws {
        self.workspaceID = workspaceID
        self.semanticFieldID = semanticFieldID
        self.kind = kind
        self.valueID = valueID
        self.privacy = privacy
        self.source = source
        self.packageReleaseID = packageReleaseID
        self.expectedRevision = expectedRevision
        self.lastAcceptedAt = lastAcceptedAt
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID
        case semanticFieldID
        case kind
        case valueID
        case privacy
        case source
        case packageReleaseID
        case expectedRevision
        case lastAcceptedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workspaceID: container.decode(UUID.self, forKey: .workspaceID),
            semanticFieldID: container.decode(String.self, forKey: .semanticFieldID),
            kind: container.decode(SuggestedInputKindV1.self, forKey: .kind),
            valueID: container.decode(String.self, forKey: .valueID),
            privacy: container.decode(SuggestedInputPrivacyV1.self, forKey: .privacy),
            source: container.decode(SuggestionSourceV1.self, forKey: .source),
            packageReleaseID: container.decode(String.self, forKey: .packageReleaseID),
            expectedRevision: container.decode(UInt64.self, forKey: .expectedRevision),
            lastAcceptedAt: container.decode(Date.self, forKey: .lastAcceptedAt)
        )
    }

    func validate() throws {
        guard workspaceID != SettingsValidationV1.zeroUUID,
              SettingsValidationV1.validToken(semanticFieldID, maximumBytes: 160),
              Self.validReference(valueID, kind: kind),
              privacy == .referenceOnlyNoRawCustomerData,
              SettingsValidationV1.validToken(packageReleaseID, maximumBytes: 160),
              lastAcceptedAt.timeIntervalSinceReferenceDate.isFinite,
              (kind == .optionID && source == .reviewedRecentOption)
                || (kind == .stableLocalReference
                    && source == .reviewedStableLocalReference) else {
            throw SettingsContractFailureV1.invalidValue
        }
    }

    var identity: String {
        workspaceID.uuidString.lowercased() + ":" + semanticFieldID + ":" + valueID
    }

    private static func validReference(_ value: String, kind: SuggestedInputKindV1) -> Bool {
        let prefix = kind == .optionID ? "option:" : "local-ref:"
        guard value.hasPrefix(prefix), value.utf8.count <= 200 else { return false }
        let suffix = String(value.dropFirst(prefix.count))
        switch kind {
        case .optionID:
            return CompatibilityCanonicalV1.validSHA256(suffix)
        case .stableLocalReference:
            guard let uuid = UUID(uuidString: suffix) else { return false }
            return uuid.uuidString.lowercased() == suffix
        }
    }
}

enum SuggestionValidationResultV1: String, CaseIterable, Codable, Sendable {
    case validForDisplay = "VALID_FOR_DISPLAY"
    case validForExplicitAcceptance = "VALID_FOR_EXPLICIT_ACCEPTANCE"
    case wrongWorkspace = "WRONG_WORKSPACE"
    case staleRevision = "STALE_REVISION"
    case packageOrOptionRetired = "PACKAGE_OR_OPTION_RETIRED"
    case hiddenOrReadOnly = "HIDDEN_OR_READ_ONLY"
    case permissionOrAvailabilityChanged = "PERMISSION_OR_AVAILABILITY_CHANGED"
    case tombstonedOrMoved = "TOMBSTONED_OR_MOVED"
    case expired = "EXPIRED"
}

struct SuggestionValidationContextV1: Sendable {
    let workspaceID: UUID
    let packageReleaseID: String
    let semanticFieldID: String
    let currentRevision: UInt64
    let allowedValueIDs: Set<String>
    let isVisibleAndWritable: Bool
    let permissionAndAvailabilitySatisfied: Bool
    let now: Date
}

struct EntryAssistPolicyV1: Codable, Equatable, Sendable {
    static let maximumSuggestionsPerField = 3
    static let maximumEntries = 128
    static let retentionSeconds: TimeInterval = 90 * 24 * 60 * 60

    let schemaVersion: Int = 1

    func validate(
        _ value: SuggestedInputV1,
        context: SuggestionValidationContextV1,
        forAcceptance: Bool
    ) -> SuggestionValidationResultV1 {
        guard value.workspaceID == context.workspaceID else { return .wrongWorkspace }
        guard value.semanticFieldID == context.semanticFieldID,
              value.packageReleaseID == context.packageReleaseID,
              context.allowedValueIDs.contains(value.valueID) else {
            return .packageOrOptionRetired
        }
        guard context.now.timeIntervalSince(value.lastAcceptedAt) >= 0,
              context.now.timeIntervalSince(value.lastAcceptedAt) <= Self.retentionSeconds else {
            return .expired
        }
        guard context.isVisibleAndWritable else { return .hiddenOrReadOnly }
        guard context.permissionAndAvailabilitySatisfied else {
            return .permissionOrAvailabilityChanged
        }
        if forAcceptance && value.expectedRevision != context.currentRevision {
            return .staleRevision
        }
        return forAcceptance ? .validForExplicitAcceptance : .validForDisplay
    }
}

struct RecentInputMemoryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    private(set) var entries: [SuggestedInputV1]

    init(entries: [SuggestedInputV1] = []) throws {
        schemaVersion = Self.schemaVersion
        self.entries = Self.ordered(entries)
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case entries
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        entries = try container.decode([SuggestedInputV1].self, forKey: .entries)
        try validate()
    }

    mutating func remember(_ value: SuggestedInputV1) throws {
        entries.removeAll { $0.identity == value.identity }
        entries.append(value)
        entries = Self.ordered(entries)
        if entries.count > EntryAssistPolicyV1.maximumEntries {
            entries.removeLast(entries.count - EntryAssistPolicyV1.maximumEntries)
        }
        try validate()
    }

    mutating func clear(workspaceID: UUID? = nil, semanticFieldID: String? = nil) {
        entries.removeAll { value in
            (workspaceID == nil || value.workspaceID == workspaceID)
                && (semanticFieldID == nil || value.semanticFieldID == semanticFieldID)
        }
    }

    mutating func suggestions(
        context: SuggestionValidationContextV1,
        policy: EntryAssistPolicyV1 = EntryAssistPolicyV1()
    ) -> [SuggestedInputV1] {
        entries.removeAll {
            policy.validate($0, context: context, forAcceptance: false) == .expired
        }
        return entries.filter {
            policy.validate($0, context: context, forAcceptance: false) == .validForDisplay
        }.prefix(EntryAssistPolicyV1.maximumSuggestionsPerField).map { $0 }
    }

    func validate() throws {
        try entries.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              entries.count <= EntryAssistPolicyV1.maximumEntries,
              Set(entries.map(\.identity)).count == entries.count,
              entries == Self.ordered(entries) else {
            throw SettingsContractFailureV1.invalidValue
        }
    }

    private static func ordered(_ values: [SuggestedInputV1]) -> [SuggestedInputV1] {
        values.sorted {
            if $0.lastAcceptedAt != $1.lastAcceptedAt {
                return $0.lastAcceptedAt > $1.lastAcceptedAt
            }
            return $0.identity < $1.identity
        }
    }
}

struct SettingsRegistryV1: Sendable {
    let descriptors: [SettingDescriptorV1]

    init(descriptors: [SettingDescriptorV1]) throws {
        self.descriptors = descriptors.sorted { $0.key < $1.key }
        try self.descriptors.forEach { try $0.validate() }
        guard !self.descriptors.isEmpty,
              Set(self.descriptors.map(\.key)).count == self.descriptors.count else {
            throw SettingsContractFailureV1.duplicateKey
        }
    }

    func descriptor(for key: String) throws -> SettingDescriptorV1 {
        guard let value = descriptors.first(where: { $0.key == key }) else {
            throw SettingsContractFailureV1.unknownKey
        }
        return value
    }

    static func current() throws -> SettingsRegistryV1 {
        let haptic = try CompatibilityCanonicalV1.encode(
            HapticFeedbackPreferenceV1.logicalDefault.isEnabled
        )
        let appLock = try CompatibilityCanonicalV1.encode(
            DeviceLocalAppLockSettingV1.disabled.isEnabled
        )
        let recent = try CompatibilityCanonicalV1.encode(RecentInputMemoryV1())
        let lastSelectedSmartView = try CompatibilityCanonicalV1.encode(
            LastSelectedSmartViewPreferenceV1.logicalDefault
        )
        let favoriteSurveyDefinitions = try CompatibilityCanonicalV1.encode(
            [SurveyDefinitionPreferenceReferenceV1]()
        )
        let recentSurveyDefinitions = try CompatibilityCanonicalV1.encode(
            [SurveyDefinitionPreferenceReferenceV1]()
        )
        let privateSystemDiscovery = try CompatibilityCanonicalV1.encode(
            PrivateSystemDiscoveryOptInV1.offToken
        )
        return try SettingsRegistryV1(descriptors: [
            try SettingDescriptorV1(
                key: DeviceLocalAppLockSettingV1.key,
                valueKind: .boolean,
                scope: .deviceLocal,
                storage: .soleDevicePreferencesAdapter,
                defaultCanonicalValue: appLock,
                maximumCanonicalBytes: 16,
                migrationVersion: DeviceLocalAppLockSettingV1.schemaVersion,
                backup: .excludedDeviceLocal,
                reset: .restoreDefault,
                erase: .restoreDefault,
                privacy: .devicePreferenceNoCustomerData,
                localizationKey: "settings.appLock",
                changesHistoricOutput: false
            ),
            try SettingDescriptorV1(
                key: HapticFeedbackPreferenceV1.key,
                valueKind: .boolean,
                scope: .deviceLocal,
                storage: .soleDevicePreferencesAdapter,
                defaultCanonicalValue: haptic,
                maximumCanonicalBytes: 128,
                migrationVersion: 1,
                backup: .excludedDeviceLocal,
                reset: .restoreDefault,
                erase: .restoreDefault,
                privacy: .devicePreferenceNoCustomerData,
                localizationKey: "settings.hapticFeedback"
            ),
            try SettingDescriptorV1(
                key: LastSelectedSmartViewPreferenceV1.key,
                valueKind: .boundedString,
                scope: .deviceLocal,
                storage: .soleDevicePreferencesAdapter,
                defaultCanonicalValue: lastSelectedSmartView,
                maximumCanonicalBytes: 200,
                migrationVersion: 1,
                backup: .excludedDeviceLocal,
                reset: .restoreDefault,
                erase: .restoreDefault,
                privacy: .devicePreferenceNoCustomerData,
                localizationKey: "settings.lastSelectedSmartView",
                changesHistoricOutput: false
            ),
            try SettingDescriptorV1(
                key: "device.recentInputMemory",
                valueKind: .recentInputMemory,
                scope: .deviceLocal,
                storage: .soleDevicePreferencesAdapter,
                defaultCanonicalValue: recent,
                maximumCanonicalBytes: SettingDescriptorV1.maximumValueBytes,
                migrationVersion: 1,
                backup: .excludedDeviceLocal,
                reset: .restoreDefault,
                erase: .restoreDefault,
                privacy: .devicePreferenceNoCustomerData,
                localizationKey: "settings.recentInputMemory"
            ),
            try SettingDescriptorV1(
                key: PrivateSystemDiscoveryOptInV1.settingKey,
                valueKind: .boundedString,
                scope: .deviceLocal,
                storage: .soleDevicePreferencesAdapter,
                defaultCanonicalValue: privateSystemDiscovery,
                maximumCanonicalBytes: 1_024,
                migrationVersion: PrivateSystemDiscoveryOptInV1.schemaVersion,
                backup: .excludedDeviceLocal,
                reset: .restoreDefault,
                erase: .restoreDefault,
                privacy: .devicePreferenceNoCustomerData,
                localizationKey: "settings.privateSystemDiscovery",
                changesHistoricOutput: false
            ),
            try SettingDescriptorV1(
                key: SurveyDefinitionDeviceMemoryV1.favoriteKey,
                valueKind: .surveyDefinitionPreferenceReferenceSet,
                scope: .deviceLocal,
                storage: .soleDevicePreferencesAdapter,
                defaultCanonicalValue: favoriteSurveyDefinitions,
                maximumCanonicalBytes: SurveyDefinitionDeviceMemoryV1.maximumCanonicalBytes,
                migrationVersion: SurveyDefinitionDeviceMemoryV1.schemaVersion,
                backup: .excludedDeviceLocal,
                reset: .restoreDefault,
                erase: .restoreDefault,
                privacy: .devicePreferenceNoCustomerData,
                localizationKey: SurveyDefinitionLocalizationKeyV1.settingsFavorite.rawValue
            ),
            try SettingDescriptorV1(
                key: SurveyDefinitionDeviceMemoryV1.recentsKey,
                valueKind: .surveyDefinitionPreferenceReferenceSet,
                scope: .deviceLocal,
                storage: .soleDevicePreferencesAdapter,
                defaultCanonicalValue: recentSurveyDefinitions,
                maximumCanonicalBytes: SurveyDefinitionDeviceMemoryV1.maximumCanonicalBytes,
                migrationVersion: SurveyDefinitionDeviceMemoryV1.schemaVersion,
                backup: .excludedDeviceLocal,
                reset: .restoreDefault,
                erase: .restoreDefault,
                privacy: .devicePreferenceNoCustomerData,
                localizationKey: SurveyDefinitionLocalizationKeyV1.settingsRecents.rawValue
            ),
        ])
    }
}

enum SettingsValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func validToken(_ value: String, maximumBytes: Int = 128) -> Bool {
        CompatibilityCanonicalV1.validToken(value, maximumUTF8ByteCount: maximumBytes)
    }
}

// MARK: - C25 device-local favorites and recents

/// A preference points at an immutable, workspace-scoped survey-definition
/// release.  It is deliberately richer than a free-form string so a device
/// preference can never become a second source of definition truth.
struct SurveyDefinitionPreferenceReferenceV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: UUID
    let definitionID: UUID
    let releaseID: UUID
    let activityKind: ActivityKindV1
    let releaseRevision: UInt64
    /// Zero is the newest recency position.  Favorites must always use zero.
    let recencyRank: UInt64

    init(
        workspaceID: UUID,
        definitionID: UUID,
        releaseID: UUID,
        activityKind: ActivityKindV1,
        releaseRevision: UInt64,
        recencyRank: UInt64 = 0
    ) throws {
        self.workspaceID = workspaceID
        self.definitionID = definitionID
        self.releaseID = releaseID
        self.activityKind = activityKind
        self.releaseRevision = releaseRevision
        self.recencyRank = recencyRank
        try validate()
    }

    init(
        release: SurveyDefinitionReleaseV1,
        recencyRank: UInt64 = 0
    ) throws {
        try self.init(
            workspaceID: release.workspaceID.rawValue,
            definitionID: release.definitionID,
            releaseID: release.releaseID,
            activityKind: release.activityKind,
            releaseRevision: release.revision,
            recencyRank: recencyRank
        )
    }

    /// Strict compatibility bridge for the former ID-only API.  The complete
    /// typed identity is required; arbitrary labels and partial IDs fail.
    init(stableStorageID: String, recencyRank: UInt64 = 0) throws {
        let pieces = stableStorageID.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 10,
              pieces[0] == "workspace",
              pieces[2] == "definition",
              pieces[4] == "release",
              pieces[6] == "activity",
              pieces[8] == "revision",
              let workspaceID = UUID(uuidString: String(pieces[1])),
              let definitionID = UUID(uuidString: String(pieces[3])),
              let releaseID = UUID(uuidString: String(pieces[5])),
              let activityKind = ActivityKindV1(rawValue: String(pieces[7])),
              let releaseRevision = UInt64(String(pieces[9])) else {
            throw SettingsContractFailureV1.invalidValue
        }
        try self.init(
            workspaceID: workspaceID,
            definitionID: definitionID,
            releaseID: releaseID,
            activityKind: activityKind,
            releaseRevision: releaseRevision,
            recencyRank: recencyRank
        )
        guard self.stableStorageID == stableStorageID else {
            throw SettingsContractFailureV1.invalidValue
        }
    }

    /// Stable identity excludes recency so duplicate list entries can be
    /// detected even when callers supplied different positions.
    var stableStorageID: String {
        "workspace.\(workspaceID.uuidString.lowercased()).definition.\(definitionID.uuidString.lowercased()).release.\(releaseID.uuidString.lowercased()).activity.\(activityKind.rawValue).revision.\(releaseRevision)"
    }

    func validate() throws {
        guard workspaceID != SettingsValidationV1.zeroUUID,
              definitionID != SettingsValidationV1.zeroUUID,
              releaseID != SettingsValidationV1.zeroUUID,
              releaseRevision > 0,
              SettingsValidationV1.validToken(stableStorageID, maximumBytes: 320) else {
            throw SettingsContractFailureV1.invalidValue
        }
    }
}

/// Source-compatible spelling for the earlier C25 type.  New persistence
/// APIs use the explicit PreferenceReference name above.
typealias SurveyDefinitionDeviceReferenceV1 = SurveyDefinitionPreferenceReferenceV1

enum SurveyDefinitionDeviceMemoryV1 {
    static let schemaVersion = 1
    static let favoriteKey = "device.surveyDefinition.favoriteIDs"
    static let recentsKey = "device.surveyDefinition.recentIDs"
    static let maximumFavorites = 64
    static let maximumRecents = 32
    static let maximumCanonicalBytes = 65_536
    static let backupDisposition = "EXCLUDED_DEVICE_LOCAL"
    static let analyticsDisposition = "EXCLUDED_DEVICE_LOCAL"
    static let searchDisposition = "EXCLUDED_DEVICE_LOCAL"
    static let reportDisposition = "EXCLUDED_DEVICE_LOCAL"
    static let canonicalTruthDisposition = "NO_CANONICAL_MUTATION"

    static func isPreferenceKey(_ key: String) -> Bool {
        key == favoriteKey || key == recentsKey
    }

    static func canonicalReferences(
        _ references: [SurveyDefinitionPreferenceReferenceV1],
        forKey key: String
    ) throws -> [SurveyDefinitionPreferenceReferenceV1] {
        try validatePolicy()
        switch key {
        case favoriteKey:
            return try canonicalFavorites(references)
        case recentsKey:
            return try canonicalRecents(references)
        default:
            throw SettingsContractFailureV1.unknownKey
        }
    }

    static func canonicalIDs(
        _ references: [SurveyDefinitionDeviceReferenceV1],
        maximum: Int
    ) throws -> [String] {
        let canonical = try canonicalFavorites(references)
        guard canonical.count <= maximum else {
            throw SettingsContractFailureV1.invalidValue
        }
        return canonical.map(\.stableStorageID)
    }

    /// Parses the compatibility ID list into typed references.  Recents use
    /// input order as the explicit recency signal, then canonicalize it.
    static func references(
        fromStableStorageIDs values: [String],
        recencyOrdered: Bool
    ) throws -> [SurveyDefinitionPreferenceReferenceV1] {
        let maximum = recencyOrdered ? maximumRecents : maximumFavorites
        guard values.count <= maximum else {
            throw SettingsContractFailureV1.invalidValue
        }
        var seen = Set<String>()
        var references: [SurveyDefinitionPreferenceReferenceV1] = []
        for value in values where seen.insert(value).inserted {
            let rank = recencyOrdered ? UInt64(references.count) : 0
            references.append(try SurveyDefinitionPreferenceReferenceV1(
                stableStorageID: value,
                recencyRank: rank
            ))
        }
        return try canonicalReferences(
            references,
            forKey: recencyOrdered ? recentsKey : favoriteKey
        )
    }

    static func validateStoredIDs(
        _ values: [String],
        maximum: Int
    ) throws {
        guard values.count <= maximum,
              Set(values).count == values.count else {
            throw SettingsContractFailureV1.invalidValue
        }
        _ = try values.map { try SurveyDefinitionPreferenceReferenceV1(
            stableStorageID: $0
        ) }
    }

    static func validatePolicy() throws {
        guard backupDisposition == "EXCLUDED_DEVICE_LOCAL",
              analyticsDisposition == "EXCLUDED_DEVICE_LOCAL",
              searchDisposition == "EXCLUDED_DEVICE_LOCAL",
              reportDisposition == "EXCLUDED_DEVICE_LOCAL",
              canonicalTruthDisposition == "NO_CANONICAL_MUTATION",
              maximumFavorites > 0, maximumRecents > 0,
              maximumCanonicalBytes <= SettingDescriptorV1.maximumValueBytes else {
            throw SettingsContractFailureV1.scopeMismatch
        }
    }

    private static func canonicalFavorites(
        _ references: [SurveyDefinitionPreferenceReferenceV1]
    ) throws -> [SurveyDefinitionPreferenceReferenceV1] {
        var byIdentity: [String: SurveyDefinitionPreferenceReferenceV1] = [:]
        for reference in references {
            try reference.validate()
            guard reference.recencyRank == 0 else {
                throw SettingsContractFailureV1.invalidValue
            }
            if let prior = byIdentity[reference.stableStorageID], prior != reference {
                throw SettingsContractFailureV1.invalidValue
            }
            byIdentity[reference.stableStorageID] = reference
        }
        let values = byIdentity.values.sorted { $0.stableStorageID < $1.stableStorageID }
        guard values.count <= maximumFavorites else {
            throw SettingsContractFailureV1.invalidValue
        }
        return values
    }

    private static func canonicalRecents(
        _ references: [SurveyDefinitionPreferenceReferenceV1]
    ) throws -> [SurveyDefinitionPreferenceReferenceV1] {
        var byIdentity: [String: SurveyDefinitionPreferenceReferenceV1] = [:]
        for reference in references {
            try reference.validate()
            if let prior = byIdentity[reference.stableStorageID] {
                guard prior.workspaceID == reference.workspaceID,
                      prior.definitionID == reference.definitionID,
                      prior.releaseID == reference.releaseID,
                      prior.activityKind == reference.activityKind,
                      prior.releaseRevision == reference.releaseRevision else {
                    throw SettingsContractFailureV1.invalidValue
                }
                if reference.recencyRank < prior.recencyRank {
                    byIdentity[reference.stableStorageID] = reference
                }
            } else {
                byIdentity[reference.stableStorageID] = reference
            }
        }
        let ordered = byIdentity.values.sorted {
            if $0.recencyRank != $1.recencyRank {
                return $0.recencyRank < $1.recencyRank
            }
            return $0.stableStorageID < $1.stableStorageID
        }
        guard ordered.count <= maximumRecents else {
            throw SettingsContractFailureV1.invalidValue
        }
        return try ordered.enumerated().map { index, reference in
            try SurveyDefinitionPreferenceReferenceV1(
                workspaceID: reference.workspaceID,
                definitionID: reference.definitionID,
                releaseID: reference.releaseID,
                activityKind: reference.activityKind,
                releaseRevision: reference.releaseRevision,
                recencyRank: UInt64(index)
            )
        }
    }
}

// MARK: - C26 guided-survey device persistence boundary

/// Canonical session lifecycle, fact, subject, and publication values never
/// become device settings.  This closed namespace is intentionally rejected
/// by the device-local descriptor and adapter; canonical writers own those
/// values and local favorites/recents remain the only survey memory.
enum SurveySessionDevicePersistenceBoundaryV1 {
    static let canonicalKeyPrefixes = [
        "survey.session.lifecycle",
        "survey.session.fact",
        "survey.session.subject",
        "survey.session.publication"
    ]
    static let canonicalTruthDisposition = "WORKSPACE_CANONICAL_ONLY"
    static let devicePersistenceDisposition = "REJECTED_DEVICE_LOCAL"
    static let backupDisposition = "EXCLUDED_DEVICE_LOCAL"
    static let searchDisposition = "DERIVED_METADATA_ONLY"
    static let reportDisposition = "CANONICAL_SNAPSHOT_ONLY"

    static func isCanonicalFactKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return canonicalKeyPrefixes.contains {
            normalized == $0 || normalized.hasPrefix($0 + ".")
        }
    }

    static func validate() -> Bool {
        canonicalTruthDisposition == "WORKSPACE_CANONICAL_ONLY"
            && devicePersistenceDisposition == "REJECTED_DEVICE_LOCAL"
            && backupDisposition == "EXCLUDED_DEVICE_LOCAL"
            && searchDisposition == "DERIVED_METADATA_ONLY"
            && reportDisposition == "CANONICAL_SNAPSHOT_ONLY"
            && canonicalKeyPrefixes == canonicalKeyPrefixes.sorted()
            && Set(canonicalKeyPrefixes).count == canonicalKeyPrefixes.count
    }
}

enum C47ActivityContractConformance_FieldEvidenceApp_Domain_Settings_SettingsContractsV1_swift {
    static let integrationRole = "INDEPENDENT_START_POLICY"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let createsSecondRouteOrInspectionAlias = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

struct ActivityContractStartPolicyV2: Codable, Equatable, Sendable {
    let installationStartEnabled: Bool
    let punchReviewStartEnabled: Bool
    let noPlanFallbackEnabled: Bool
    let unknownKindReadExportEnabled: Bool

    func permitsNewStart(for kind: ActivityKindV2) -> Bool {
        switch kind {
        case .installation: return installationStartEnabled
        case .punchReview: return punchReviewStartEnabled
        case .unknown: return false
        default: return true
        }
    }

    static let disablesReadExportRecoveryWhenStartDisabled = false
    static let requiresPlanOrScanProvider = false
}

/// Closeout presentation is canonical envelope truth and cannot be hidden,
/// reclassified, or replaced by a device preference.
enum ActivityContractCloseoutSettingsPolicyV2 {
    static func validateCanonicalPresentation(_ envelope: ActivitySessionEnvelopeV2) throws {
        try envelope.validateForRead()
        try envelope.installationCloseout?.validate()
        try envelope.punchReviewCloseout?.validate()
    }
    static let devicePreferenceMayHideCloseout = false
    static let devicePreferenceMayOverrideFindingTruth = false
}

import Foundation

protocol LocalAuthenticationClient: Sendable {
    func availability() async -> LocalAuthenticationAvailabilityV1
    func authenticate(
        _ attempt: LocalAuthenticationAttemptV1
    ) async -> LocalAuthenticationOutcomeV1
    func cancel(attemptID: UUID) async
}

enum DeviceLocalAppLockSettingReadV1: Equatable, Sendable {
    case absentDisabled
    case value(DeviceLocalAppLockSettingV1)
    case corruptOrAmbiguous
    case protectedDataUnavailable
}

struct DeviceLocalAppLockSettingWriteReceiptV1: Equatable, Sendable {
    let operationID: UUID
    let value: DeviceLocalAppLockSettingV1
    let adoptedExistingEffect: Bool
}

protocol DeviceLocalAppLockSettingPortV1: Sendable {
    func readAppLockSetting() async -> DeviceLocalAppLockSettingReadV1
    func writeAppLockSetting(
        _ value: DeviceLocalAppLockSettingV1,
        operationID: UUID
    ) async throws -> DeviceLocalAppLockSettingWriteReceiptV1
    func eraseAppLockSetting(operationID: UUID) async throws
}

struct ProtectedIngressStageRequestV1: Equatable, Sendable {
    let intentID: UUID
    let operationID: UUID
    let kind: LockedIngressKindV1
    let byteCount: UInt64
    let receivedAt: Date
    let expiresAt: Date
}

struct ProtectedIngressStageReceiptV1: Equatable, Sendable {
    let intent: PendingLockedExternalIntentV1
    let disposition: LockedIngressDispositionV1
    let adoptedExistingEffect: Bool
}

struct ProtectedIngressStartupHygieneReceiptV1: Equatable, Sendable {
    static let maximumInspectedCount = 128
    let operationID: UUID
    let inspectedCount: Int
    let removedKnownOwnedCount: Int
    let retainedValidCount: Int
    let deferredAmbiguousCount: Int
    let contentRead: Bool

    init(
        operationID: UUID,
        inspectedCount: Int,
        removedKnownOwnedCount: Int,
        retainedValidCount: Int,
        deferredAmbiguousCount: Int,
        contentRead: Bool
    ) throws {
        self.operationID = operationID
        self.inspectedCount = inspectedCount
        self.removedKnownOwnedCount = removedKnownOwnedCount
        self.retainedValidCount = retainedValidCount
        self.deferredAmbiguousCount = deferredAmbiguousCount
        self.contentRead = contentRead
        guard operationID != SettingsValidationV1.zeroUUID,
              inspectedCount >= 0,
              inspectedCount <= Self.maximumInspectedCount,
              removedKnownOwnedCount >= 0,
              removedKnownOwnedCount <= Self.maximumInspectedCount,
              retainedValidCount >= 0,
              retainedValidCount <= Self.maximumInspectedCount,
              deferredAmbiguousCount >= 0,
              deferredAmbiguousCount <= Self.maximumInspectedCount,
              removedKnownOwnedCount + retainedValidCount
                + deferredAmbiguousCount == inspectedCount,
              !contentRead else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    var requiresAuthenticatedRecovery: Bool { deferredAmbiguousCount > 0 }
}

protocol ProtectedIngressStoreV1: Sendable {
    /// Metadata-only startup hygiene. It may inspect bounded ownership,
    /// protection, age, and identity metadata, but never payload bytes.
    func performBlindStartupHygiene(
        now: Date,
        operationID: UUID
    ) async throws -> ProtectedIngressStartupHygieneReceiptV1
    /// The effect must copy bytes without parsing, previewing, indexing,
    /// deserializing, logging, or deriving work/customer facts.
    func stageContentBlind(
        _ request: ProtectedIngressStageRequestV1,
        source: URL
    ) async throws -> ProtectedIngressStageReceiptV1
    func pendingIntents() async throws -> [PendingLockedExternalIntentV1]
    func markReadyForAuthenticatedValidation(intentID: UUID) async throws
        -> PendingLockedExternalIntentV1
    func remove(intentID: UUID, disposition: LockedIngressDispositionV1) async throws
    func eraseAllProtectedIngress(operationID: UUID) async throws
}

/// Low-level authority for an adopted durable ingress implementation. Each
/// mutation must be descriptor-pinned, atomic, idempotent by the supplied
/// expected value, and return only after an exact durable readback.
protocol ProtectedIngressDurableEffectPortV1: Sendable {
    /// Atomically removes only proven-owned expired/interrupted staging and
    /// reports ambiguous metadata for authenticated recovery. Payload content
    /// must not be opened, parsed, decrypted, previewed, or indexed.
    func performBlindStartupHygieneEffect(
        now: Date,
        operationID: UUID
    ) async throws -> ProtectedIngressStartupHygieneReceiptV1
    func readBlindStartupHygieneReceiptEffect(
        operationID: UUID
    ) async throws -> ProtectedIngressStartupHygieneReceiptV1
    func loadPendingIntentsEffect() async throws -> [PendingLockedExternalIntentV1]
    func stageContentBlindEffect(
        _ request: ProtectedIngressStageRequestV1,
        source: URL
    ) async throws -> PendingLockedExternalIntentV1
    func replacePendingIntentEffect(
        expected: PendingLockedExternalIntentV1,
        replacement: PendingLockedExternalIntentV1
    ) async throws
    func removePendingIntentEffect(
        expected: PendingLockedExternalIntentV1,
        disposition: LockedIngressDispositionV1
    ) async throws
    func erasePendingIntentsEffect(operationID: UUID) async throws
}

struct AppLockNotificationCanonicalPolicyV1: Codable, Equatable, Sendable {
    let policyID: String
    let revision: UInt64
    let canonicalDigest: String

    func validate() throws {
        guard SettingsValidationV1.validToken(policyID, maximumBytes: 160),
              CompatibilityCanonicalV1.validSHA256(canonicalDigest) else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    init(policyID: String, revision: UInt64, canonicalDigest: String) {
        self.policyID = policyID
        self.revision = revision
        self.canonicalDigest = canonicalDigest
    }

    private enum CodingKeys: String, CodingKey { case policyID, revision, canonicalDigest }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            policyID: try values.decode(String.self, forKey: .policyID),
            revision: try values.decode(UInt64.self, forKey: .revision),
            canonicalDigest: try values.decode(String.self, forKey: .canonicalDigest)
        )
        try validate()
    }
}

struct AppLockGenericNotificationV1: Codable, Equatable, Sendable {
    let requestID: String
    let opaqueCorrelationToken: String
    let title: String
    let body: String

    func validate() throws {
        guard SettingsValidationV1.validToken(requestID, maximumBytes: 160),
              CompatibilityCanonicalV1.validSHA256(opaqueCorrelationToken),
              title == AppLockCopyV1.genericNotificationTitle,
              body == AppLockCopyV1.genericNotificationBody else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    init(
        requestID: String,
        opaqueCorrelationToken: String,
        title: String = AppLockCopyV1.genericNotificationTitle,
        body: String = AppLockCopyV1.genericNotificationBody
    ) {
        self.requestID = requestID
        self.opaqueCorrelationToken = opaqueCorrelationToken
        self.title = title
        self.body = body
    }

    private enum CodingKeys: String, CodingKey {
        case requestID, opaqueCorrelationToken, title, body
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            requestID: try values.decode(String.self, forKey: .requestID),
            opaqueCorrelationToken: try values.decode(String.self, forKey: .opaqueCorrelationToken),
            title: try values.decode(String.self, forKey: .title),
            body: try values.decode(String.self, forKey: .body)
        )
        try validate()
    }
}

struct AppLockNotificationJournalV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let operationID: UUID
    let targetEnabled: Bool
    let priorPolicy: AppLockNotificationCanonicalPolicyV1
    let projections: [AppLockGenericNotificationV1]
    let disposition: AppLockNotificationPrivacyDispositionV1

    init(
        operationID: UUID,
        targetEnabled: Bool,
        priorPolicy: AppLockNotificationCanonicalPolicyV1,
        projections: [AppLockGenericNotificationV1],
        disposition: AppLockNotificationPrivacyDispositionV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.targetEnabled = targetEnabled
        self.priorPolicy = priorPolicy
        self.projections = projections.sorted { $0.requestID < $1.requestID }
        self.disposition = disposition
        guard operationID != SettingsValidationV1.zeroUUID,
              self.projections.count <= 1_024,
              Set(self.projections.map(\.requestID)).count == self.projections.count,
              Self.valid(disposition: disposition, targetEnabled: targetEnabled) else {
            throw AppAccessContractFailureV1.invalidValue
        }
        try priorPolicy.validate()
        try self.projections.forEach { try $0.validate() }
    }

    private static func valid(
        disposition: AppLockNotificationPrivacyDispositionV1,
        targetEnabled: Bool
    ) -> Bool {
        switch disposition {
        case .enablingPrepared, .genericProjectionApplied, .genericProjectionAdopted:
            return targetEnabled
        case .disablingPrepared, .priorPolicyRebuilt:
            return !targetEnabled
        case .interruptedRecoveryRequired:
            return true
        case .unchangedDisabled, .erased:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, operationID, targetEnabled, priorPolicy, projections, disposition
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try self.init(
            operationID: values.decode(UUID.self, forKey: .operationID),
            targetEnabled: values.decode(Bool.self, forKey: .targetEnabled),
            priorPolicy: values.decode(
                AppLockNotificationCanonicalPolicyV1.self,
                forKey: .priorPolicy
            ),
            projections: values.decode(
                [AppLockGenericNotificationV1].self,
                forKey: .projections
            ),
            disposition: values.decode(
                AppLockNotificationPrivacyDispositionV1.self,
                forKey: .disposition
            )
        )
    }
}

protocol AppLockNotificationPrivacyPortV1: Sendable {
    func loadJournal() async throws -> AppLockNotificationJournalV1?
    func prepareEnable(operationID: UUID) async throws -> AppLockNotificationJournalV1
    func applyGenericProjection(
        _ journal: AppLockNotificationJournalV1
    ) async throws -> AppLockNotificationPrivacyDispositionV1
    func prepareDisable(operationID: UUID) async throws -> AppLockNotificationJournalV1
    func rebuildPriorPolicy(
        _ journal: AppLockNotificationJournalV1
    ) async throws -> AppLockNotificationPrivacyDispositionV1
    func resolveOpaqueTokenAfterAuthentication(
        _ token: String,
        now: Date
    ) async throws -> String?
    func eraseNotificationsAndMappings(operationID: UUID) async throws
}

/// Injected durable/system boundary used by the production privacy
/// coordinator. Implementations atomically persist the journal before changing
/// notification state, and every returned journal is an exact readback.
protocol AppLockNotificationEffectPortV1: Sendable {
    func loadJournalEffect() async throws -> AppLockNotificationJournalV1?
    func prepareEnableEffect(operationID: UUID) async throws -> AppLockNotificationJournalV1
    func publishGenericEffect(
        expected: AppLockNotificationJournalV1
    ) async throws -> AppLockNotificationJournalV1
    func prepareDisableEffect(operationID: UUID) async throws -> AppLockNotificationJournalV1
    func rebuildPriorPolicyEffect(
        expected: AppLockNotificationJournalV1
    ) async throws -> AppLockNotificationJournalV1
    func resolveOpaqueTokenEffect(_ token: String, now: Date) async throws -> String?
    func eraseNotificationsAndMappingsEffect(operationID: UUID) async throws
}

protocol AppAccessGatePortV1: Sendable {
    func currentState() async -> AppAccessStateV1
    func lock(reason: AppLockReasonV1) async
    func authenticate(trigger: LocalAuthenticationTriggerV1) async
        -> LocalAuthenticationOutcomeV1
    func requireContentAccess() async throws
}

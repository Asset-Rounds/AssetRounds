import Foundation

/// Opens only the application's public iOS Settings destination. Callers
/// cannot provide a URL, scheme, or a private language-settings route.
@MainActor
protocol GlobalizationSystemSettingsPortV1 {
    func openAppSettings() async -> Bool
}

protocol SettingsRegistryPortV1: Sendable {
    func descriptor(for key: String) throws -> SettingDescriptorV1
}

extension SettingsRegistryV1: SettingsRegistryPortV1 {}

protocol DevicePreferencesPortV1: Sendable {
    func readCanonicalValue(for descriptor: SettingDescriptorV1) throws -> Data
    func writeCanonicalValue(
        _ value: Data,
        descriptor: SettingDescriptorV1,
        operationID: UUID
    ) throws
    func migrate(
        descriptor: SettingDescriptorV1,
        legacyKeys: [String],
        operationID: UUID
    ) throws -> SettingsMigrationReceiptV1
    func reset(descriptors: [SettingDescriptorV1], operationID: UUID) throws
    func erase(descriptors: [SettingDescriptorV1], operationID: UUID) throws
}

protocol PrivateSystemDiscoveryPreferencePortV1: Sendable {
    func readPrivateSystemDiscoveryOptIn() throws -> PrivateSystemDiscoveryOptInV1
    func writePrivateSystemDiscoveryOptIn(_ value: PrivateSystemDiscoveryOptInV1, operationID: UUID) throws
    func migratePrivateSystemDiscoveryOptIn(operationID: UUID) throws -> PrivateSystemDiscoveryOptInV1
}

extension PreferencesAdapterV1: PrivateSystemDiscoveryPreferencePortV1 {}

/// Typed C16 device-local settings boundary. No caller receives a raw defaults
/// key, and neither value participates in backup, restore, clone, or export.
protocol WorkspaceExperienceDevicePreferencesPortV1: Sendable {
    func activeWorkspaceSelection() throws -> ActiveWorkspaceSelectionV1?
    func setActiveWorkspaceSelection(_ value: ActiveWorkspaceSelectionV1?, operationID: UUID) throws
    func noticeAcknowledgement() throws -> NoticeAcknowledgementV1?
    func setNoticeAcknowledgement(_ value: NoticeAcknowledgementV1?, operationID: UUID) throws
}

extension PreferencesAdapterV1: WorkspaceExperienceDevicePreferencesPortV1 {}

struct WorkspaceSettingWriteCommandV1: Sendable {
    let workspaceID: UUID
    let key: String
    let canonicalValue: Data
    let expectedRevision: UInt64
    let mutationID: UUID

    init(
        workspaceID: UUID,
        descriptor: SettingDescriptorV1,
        canonicalValue: Data,
        expectedRevision: UInt64,
        mutationID: UUID
    ) throws {
        self.workspaceID = workspaceID
        self.key = descriptor.key
        self.canonicalValue = canonicalValue
        self.expectedRevision = expectedRevision
        self.mutationID = mutationID
        try descriptor.validate()
        guard descriptor.scope == .workspaceCanonical,
              descriptor.storage == .workspaceWriter,
              workspaceID != SettingsValidationV1.zeroUUID,
              mutationID != SettingsValidationV1.zeroUUID,
              SettingsValidationV1.validToken(descriptor.key, maximumBytes: 160) else {
            throw SettingsContractFailureV1.invalidValue
        }
        try descriptor.validateCanonicalValue(canonicalValue)
    }
}

struct WorkspaceSettingWriteReceiptV1: Codable, Equatable, Sendable {
    let mutationID: UUID
    let workspaceID: UUID
    let key: String
    let resultingRevision: UInt64
    let canonicalValueDigest: String
    let adoptedExistingEffect: Bool

    init(
        mutationID: UUID,
        workspaceID: UUID,
        key: String,
        resultingRevision: UInt64,
        canonicalValueDigest: String,
        adoptedExistingEffect: Bool
    ) throws {
        self.mutationID = mutationID
        self.workspaceID = workspaceID
        self.key = key
        self.resultingRevision = resultingRevision
        self.canonicalValueDigest = canonicalValueDigest
        self.adoptedExistingEffect = adoptedExistingEffect
        guard mutationID != SettingsValidationV1.zeroUUID,
              workspaceID != SettingsValidationV1.zeroUUID,
              SettingsValidationV1.validToken(key, maximumBytes: 160),
              CompatibilityCanonicalV1.validSHA256(canonicalValueDigest) else {
            throw SettingsContractFailureV1.invalidValue
        }
    }
}

protocol WorkspaceCanonicalSettingPortV1: Sendable {
    func readWorkspaceSetting(
        workspaceID: UUID,
        key: String
    ) async throws -> WorkspaceSettingRecordV1?
    func writeWorkspaceSetting(
        _ command: WorkspaceSettingWriteCommandV1
    ) async throws -> WorkspaceSettingWriteReceiptV1
}

enum PermissionRequestTriggerV1: String, CaseIterable, Codable, Sendable {
    case explicitUserInitiatedFeatureBoundary = "EXPLICIT_USER_INITIATED_FEATURE_BOUNDARY"
}

struct PermissionRequestBoundaryV1: Equatable, Sendable {
    let operationID: UUID
    let capabilityID: CapabilityIDV1
    let trigger: PermissionRequestTriggerV1
    let userInitiatedAt: Date

    init(
        operationID: UUID,
        capabilityID: CapabilityIDV1,
        trigger: PermissionRequestTriggerV1,
        userInitiatedAt: Date
    ) throws {
        self.operationID = operationID
        self.capabilityID = capabilityID
        self.trigger = trigger
        self.userInitiatedAt = userInitiatedAt
        guard operationID != SettingsValidationV1.zeroUUID,
              trigger == .explicitUserInitiatedFeatureBoundary,
              userInitiatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CapabilityContractFailureV1.permissionRequestNotUserInitiated
        }
    }
}

protocol CapabilityRuntimePortV1: Sendable {
    func state(for capabilityID: CapabilityIDV1) async throws -> CapabilityStateV1
    func requestPermission(
        for capabilityID: CapabilityIDV1,
        boundary: PermissionRequestBoundaryV1
    ) async throws -> CapabilityStateV1
}

protocol HapticRuntimePortV1: Sendable {
    func isAvailable() async -> Bool
    func emitSuccess() async
    func emitWarning() async
}

protocol BundledFeaturePolicyDataPortV1: Sendable {
    func canonicalFeaturePolicyData() throws -> Data
    func buildArtifactDigest() throws -> String
}

struct CapabilityScratchLeaseRequestV1: Equatable, Sendable {
    let leaseID: UUID
    let operationID: UUID
    let purpose: CapabilityScratchPurposeV1
    let requestedByteCount: UInt64
    let createdAt: Date
    let expiresAt: Date

    init(
        leaseID: UUID,
        operationID: UUID,
        purpose: CapabilityScratchPurposeV1,
        requestedByteCount: UInt64,
        createdAt: Date,
        expiresAt: Date
    ) throws {
        self.leaseID = leaseID
        self.operationID = operationID
        self.purpose = purpose
        self.requestedByteCount = requestedByteCount
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        guard leaseID != SettingsValidationV1.zeroUUID,
              operationID != SettingsValidationV1.zeroUUID,
              purpose != .none,
              requestedByteCount > 0,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > createdAt else {
            throw CapabilityContractFailureV1.invalidValue
        }
    }
}

struct CapabilityScratchLeaseV1: Equatable, Sendable {
    let leaseID: UUID
    let purpose: CapabilityScratchPurposeV1
    let relativeDirectory: String
}

protocol CapabilityScratchLeasePortV1: Sendable {
    func acquire(_ request: CapabilityScratchLeaseRequestV1) async throws
        -> CapabilityScratchLeaseV1
    func write(_ data: Data, named: String, lease: CapabilityScratchLeaseV1) async throws
        -> URL
    func finish(
        lease: CapabilityScratchLeaseV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws -> ScratchPublicationLinkageReceiptV1
    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1
}

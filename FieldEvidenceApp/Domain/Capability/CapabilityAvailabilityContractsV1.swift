import Foundation

enum ScheduleNotificationCapabilityBoundaryV1 { static let permissionIsCanonicalScheduleTruth = false }

enum C51ScheduleCapabilityBoundaryV1 {
    static let localOnly = true
    static let eventKitPermissionRequested = false
    static let externalCalendarIntegration = false
    static let reminderCapabilityForSchedule: CapabilityIDV1 = .notifications
    static let permissionRequestTiming: PermissionRequestTimingV1 = .neverRequested
    static let scheduleClosureMetadataIsDerivedOnly = true
}

enum CapabilityContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case duplicateCapability
    case duplicateFeature
    case unknownCapability
    case unknownFeature
    case unavailableCoreOperation
    case permissionRequestNotUserInitiated
    case invalidCaptureTransition
    case invalidScratchLinkage
}

enum FeatureAvailabilityReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case available = "AVAILABLE"
    case packageNotEnabled = "PACKAGE_NOT_ENABLED"
    case notEntitled = "NOT_ENTITLED"
    case unsupportedOSOrDevice = "UNSUPPORTED_OS_OR_DEVICE"
    case permissionNotDetermined = "PERMISSION_NOT_DETERMINED"
    case permissionLimited = "PERMISSION_LIMITED"
    case permissionDenied = "PERMISSION_DENIED"
    case permissionRestricted = "PERMISSION_RESTRICTED"
    case offlineContentMissing = "OFFLINE_CONTENT_MISSING"
    case recoveryBlocked = "RECOVERY_BLOCKED"
    case workspacePolicyDisabled = "WORKSPACE_POLICY_DISABLED"
    case packageRetired = "PACKAGE_RETIRED"
    case temporarilyUnavailable = "TEMPORARILY_UNAVAILABLE"
}

enum FeatureAvailabilityNextActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case begin = "BEGIN"
    case enablePackage = "ENABLE_PACKAGE"
    case viewSubscription = "VIEW_SUBSCRIPTION"
    case useManualPath = "USE_MANUAL_PATH"
    case requestPermissionAtFeatureBoundary = "REQUEST_PERMISSION_AT_FEATURE_BOUNDARY"
    case openSystemSettings = "OPEN_SYSTEM_SETTINGS"
    case downloadBundledContent = "DOWNLOAD_BUNDLED_CONTENT"
    case recoverLocalData = "RECOVER_LOCAL_DATA"
    case changeWorkspacePolicy = "CHANGE_WORKSPACE_POLICY"
    case chooseCurrentPackage = "CHOOSE_CURRENT_PACKAGE"
    case retry = "RETRY"
}

enum EssentialOperationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case priorRead = "PRIOR_READ"
    case export = "EXPORT"
    case backup = "BACKUP"
    case restore = "RESTORE"
    case recovery = "RECOVERY"
    case delete = "DELETE"
    case erase = "ERASE"
}

struct FeatureAvailabilityDecisionV1: Codable, Equatable, Sendable {
    let reason: FeatureAvailabilityReasonV1
    let nextAction: FeatureAvailabilityNextActionV1
    let manualFallbackCapabilityID: CapabilityIDV1?
    let mayStartNewOperation: Bool
    let preservesEssentialOperations: Bool
}

struct FeatureAvailabilityInputsV1: Equatable, Sendable {
    let packageEnabled: Bool
    let entitled: Bool
    let osAndDeviceSupported: Bool
    let permission: CapabilityPermissionStateV1
    let offlineContentAvailable: Bool
    let recoveryReady: Bool
    let workspacePolicyEnabled: Bool
    let packageRetired: Bool
    let temporarilyAvailable: Bool
}

struct FeatureAvailabilityPolicyV1: Sendable {
    func evaluate(
        _ inputs: FeatureAvailabilityInputsV1,
        manualFallbackCapabilityID: CapabilityIDV1?
    ) -> FeatureAvailabilityDecisionV1 {
        let reason: FeatureAvailabilityReasonV1
        if inputs.packageRetired { reason = .packageRetired }
        else if !inputs.recoveryReady { reason = .recoveryBlocked }
        else if !inputs.packageEnabled { reason = .packageNotEnabled }
        else if !inputs.entitled { reason = .notEntitled }
        else if !inputs.osAndDeviceSupported { reason = .unsupportedOSOrDevice }
        else if !inputs.workspacePolicyEnabled { reason = .workspacePolicyDisabled }
        else if !inputs.offlineContentAvailable { reason = .offlineContentMissing }
        else {
            switch inputs.permission {
            case .notDetermined: reason = .permissionNotDetermined
            case .limited: reason = .permissionLimited
            case .denied: reason = .permissionDenied
            case .restricted: reason = .permissionRestricted
            case .authorized, .notRequired:
                reason = inputs.temporarilyAvailable ? .available : .temporarilyUnavailable
            }
        }
        return FeatureAvailabilityDecisionV1(
            reason: reason,
            nextAction: Self.nextAction(for: reason),
            manualFallbackCapabilityID: reason == .available ? nil : manualFallbackCapabilityID,
            mayStartNewOperation: reason == .available,
            preservesEssentialOperations: true
        )
    }

    func requireEssentialOperationVisible(
        _ operation: EssentialOperationV1,
        decision: FeatureAvailabilityDecisionV1
    ) throws {
        guard decision.preservesEssentialOperations else {
            throw CapabilityContractFailureV1.unavailableCoreOperation
        }
        _ = operation
    }

    static func nextAction(
        for reason: FeatureAvailabilityReasonV1
    ) -> FeatureAvailabilityNextActionV1 {
        switch reason {
        case .available: return .begin
        case .packageNotEnabled: return .enablePackage
        case .notEntitled: return .viewSubscription
        case .unsupportedOSOrDevice, .permissionLimited: return .useManualPath
        case .permissionNotDetermined: return .requestPermissionAtFeatureBoundary
        case .permissionDenied, .permissionRestricted: return .openSystemSettings
        case .offlineContentMissing: return .downloadBundledContent
        case .recoveryBlocked: return .recoverLocalData
        case .workspacePolicyDisabled: return .changeWorkspacePolicy
        case .packageRetired: return .chooseCurrentPackage
        case .temporarilyUnavailable: return .retry
        }
    }
}

enum CapabilityIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case camera = "CAMERA"
    case scanOCR = "SCAN_OCR"
    case speechDictation = "SPEECH_DICTATION"
    case microphone = "MICROPHONE"
    case audioCapture = "AUDIO_CAPTURE"
    case videoCapture = "VIDEO_CAPTURE"
    case photoLibrary = "PHOTO_LIBRARY"
    case location = "LOCATION"
    case reminders = "REMINDERS"
    case notifications = "NOTIFICATIONS"
    case filesAndShare = "FILES_AND_SHARE"
    case diagnostics = "DIAGNOSTICS"
    case haptics = "HAPTICS"
    case encryptedBackup = "ENCRYPTED_BACKUP"
}

enum CapabilityPermissionStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case notRequired = "NOT_REQUIRED"
    case notDetermined = "NOT_DETERMINED"
    case authorized = "AUTHORIZED"
    case limited = "LIMITED"
    case denied = "DENIED"
    case restricted = "RESTRICTED"
}

enum CapabilityRuntimeStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case available = "AVAILABLE"
    case unavailable = "UNAVAILABLE"
    case interrupted = "INTERRUPTED"
    case unsupported = "UNSUPPORTED"
}

struct CapabilityStateV1: Codable, Equatable, Sendable {
    let capabilityID: CapabilityIDV1
    let permission: CapabilityPermissionStateV1
    let runtime: CapabilityRuntimeStateV1
    let observedAt: Date

    init(
        capabilityID: CapabilityIDV1,
        permission: CapabilityPermissionStateV1,
        runtime: CapabilityRuntimeStateV1,
        observedAt: Date
    ) throws {
        self.capabilityID = capabilityID
        self.permission = permission
        self.runtime = runtime
        self.observedAt = observedAt
        guard observedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CapabilityContractFailureV1.invalidValue
        }
    }
}

enum PermissionRequestTimingV1: String, Codable, Sendable {
    case explicitUserInitiatedFeatureBoundary = "EXPLICIT_USER_INITIATED_FEATURE_BOUNDARY"
    case neverRequested = "NEVER_REQUESTED"
}

enum ManualFallbackActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case chooseExistingPhoto = "CHOOSE_EXISTING_PHOTO"
    case typeManually = "TYPE_MANUALLY"
    case importFile = "IMPORT_FILE"
    case leaveIncompleteAndResume = "LEAVE_INCOMPLETE_AND_RESUME"
    case openSystemSettings = "OPEN_SYSTEM_SETTINGS"
    case saveLocally = "SAVE_LOCALLY"
    case noFallback = "NO_FALLBACK"
}

enum CapabilityScratchPurposeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case capture = "CAPTURE"
    case importData = "IMPORT"
    case source = "SOURCE"
    case supportExport = "SUPPORT_EXPORT"
    case none = "NONE"
}

struct CapabilityPermissionDescriptorV1: Codable, Equatable, Sendable {
    let capabilityID: CapabilityIDV1
    let platformAPI: String
    let purposeStringKey: String?
    let requestTiming: PermissionRequestTimingV1
    let manualFallback: ManualFallbackActionV1
    let scratchPurpose: CapabilityScratchPurposeV1
    let packageRequired: Bool
    let privacyDisclosureKey: String

    init(
        capabilityID: CapabilityIDV1,
        platformAPI: String,
        purposeStringKey: String?,
        requestTiming: PermissionRequestTimingV1,
        manualFallback: ManualFallbackActionV1,
        scratchPurpose: CapabilityScratchPurposeV1,
        packageRequired: Bool,
        privacyDisclosureKey: String
    ) throws {
        self.capabilityID = capabilityID
        self.platformAPI = platformAPI
        self.purposeStringKey = purposeStringKey
        self.requestTiming = requestTiming
        self.manualFallback = manualFallback
        self.scratchPurpose = scratchPurpose
        self.packageRequired = packageRequired
        self.privacyDisclosureKey = privacyDisclosureKey
        guard SettingsValidationV1.validToken(platformAPI, maximumBytes: 160),
              SettingsValidationV1.validToken(privacyDisclosureKey, maximumBytes: 160),
              purposeStringKey.map({ SettingsValidationV1.validToken($0, maximumBytes: 160) }) ?? true else {
            throw CapabilityContractFailureV1.invalidValue
        }
    }
}

struct CapabilityPermissionMatrixV1: Sendable {
    let descriptors: [CapabilityPermissionDescriptorV1]

    init(descriptors: [CapabilityPermissionDescriptorV1]) throws {
        self.descriptors = descriptors.sorted { $0.capabilityID.rawValue < $1.capabilityID.rawValue }
        guard Set(self.descriptors.map(\.capabilityID)) == Set(CapabilityIDV1.allCases),
              self.descriptors.count == CapabilityIDV1.allCases.count else {
            throw CapabilityContractFailureV1.duplicateCapability
        }
    }

    func descriptor(for capabilityID: CapabilityIDV1) throws -> CapabilityPermissionDescriptorV1 {
        guard let value = descriptors.first(where: { $0.capabilityID == capabilityID }) else {
            throw CapabilityContractFailureV1.unknownCapability
        }
        return value
    }

    static func current() throws -> Self {
        let userRequested: Set<CapabilityIDV1> = [
            .camera, .speechDictation, .microphone, .audioCapture,
            .videoCapture, .location, .reminders, .notifications,
        ]
        func item(
            _ id: CapabilityIDV1, _ api: String, _ purpose: String?,
            _ fallback: ManualFallbackActionV1, _ scratch: CapabilityScratchPurposeV1
        ) throws -> CapabilityPermissionDescriptorV1 {
            try CapabilityPermissionDescriptorV1(
                capabilityID: id,
                platformAPI: api,
                purposeStringKey: purpose,
                requestTiming: userRequested.contains(id)
                    ? .explicitUserInitiatedFeatureBoundary : .neverRequested,
                manualFallback: fallback,
                scratchPurpose: scratch,
                packageRequired: [.scanOCR, .speechDictation, .audioCapture, .videoCapture].contains(id),
                privacyDisclosureKey: "privacy.capability." + id.rawValue.lowercased()
            )
        }
        return try Self(descriptors: [
            item(.camera, "AVFoundation.video", "NSCameraUsageDescription", .chooseExistingPhoto, .capture),
            item(.scanOCR, "Vision.documentRecognition", nil, .typeManually, .source),
            item(.speechDictation, "Speech.recognition", "NSSpeechRecognitionUsageDescription", .typeManually, .source),
            item(.microphone, "AVFoundation.audio", "NSMicrophoneUsageDescription", .typeManually, .capture),
            item(.audioCapture, "AVFoundation.audioCapture", "NSMicrophoneUsageDescription", .typeManually, .capture),
            item(.videoCapture, "AVFoundation.videoCapture", "NSCameraUsageDescription", .chooseExistingPhoto, .capture),
            item(.photoLibrary, "PhotosUI.picker", nil, .importFile, .importData),
            item(.location, "CoreLocation.whenInUse", "NSLocationWhenInUseUsageDescription", .typeManually, .source),
            item(.reminders, "EventKit.reminders", "NSRemindersFullAccessUsageDescription", .typeManually, .none),
            item(.notifications, "UserNotifications", nil, .saveLocally, .none),
            item(.filesAndShare, "UniformTypeIdentifiers", nil, .saveLocally, .importData),
            item(.diagnostics, "MetricKit.local", nil, .saveLocally, .supportExport),
            item(.haptics, "UIKit.feedbackGenerator", nil, .noFallback, .none),
            item(.encryptedBackup, "AssetRounds.encryptedPortableEnvelope", nil, .saveLocally, .none),
        ])
    }
}

struct PermissionFallbackRegistryV1: Sendable {
    let matrix: CapabilityPermissionMatrixV1

    func fallback(
        for capabilityID: CapabilityIDV1,
        permission: CapabilityPermissionStateV1
    ) throws -> ManualFallbackActionV1 {
        let descriptor = try matrix.descriptor(for: capabilityID)
        return permission == .authorized || permission == .notRequired
            ? .noFallback : descriptor.manualFallback
    }
}

struct CapabilityUseReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let capabilityID: CapabilityIDV1
    let state: CapabilityStateV1
    let userInitiated: Bool
    let explicitConsent: Bool
    let fallbackUsed: ManualFallbackActionV1?
    let createdCanonicalEffect: Bool

    init(
        operationID: UUID,
        capabilityID: CapabilityIDV1,
        state: CapabilityStateV1,
        userInitiated: Bool,
        explicitConsent: Bool,
        fallbackUsed: ManualFallbackActionV1?,
        createdCanonicalEffect: Bool
    ) throws {
        self.operationID = operationID
        self.capabilityID = capabilityID
        self.state = state
        self.userInitiated = userInitiated
        self.explicitConsent = explicitConsent
        self.fallbackUsed = fallbackUsed
        self.createdCanonicalEffect = createdCanonicalEffect
        guard operationID != SettingsValidationV1.zeroUUID,
              capabilityID == state.capabilityID,
              !createdCanonicalEffect || (userInitiated && explicitConsent
                && state.permission == .authorized && state.runtime == .available) else {
            throw CapabilityContractFailureV1.invalidValue
        }
    }
}

enum ActiveCaptureKindV1: String, CaseIterable, Codable, Sendable {
    case camera = "CAMERA"
    case microphone = "MICROPHONE"
    case speech = "SPEECH"
    case audio = "AUDIO"
    case video = "VIDEO"
}

enum ActiveCapturePhaseV1: String, CaseIterable, Codable, Sendable {
    case awaitingExplicitConsent = "AWAITING_EXPLICIT_CONSENT"
    case consentedNotCapturing = "CONSENTED_NOT_CAPTURING"
    case capturingIndicatorVisible = "CAPTURING_INDICATOR_VISIBLE"
    case stopped = "STOPPED"
    case interrupted = "INTERRUPTED"
}

struct ActiveCapturePresentationContractV1: Codable, Equatable, Sendable {
    let captureID: UUID
    let kind: ActiveCaptureKindV1
    let phase: ActiveCapturePhaseV1
    let explicitConsentRecorded: Bool
    let indicatorVisibleOrAudible: Bool
    let indicatorAccessibilityLabelKey: String?
    let indicatorPersistsAcrossSceneInactivity: Bool

    init(
        captureID: UUID,
        kind: ActiveCaptureKindV1,
        phase: ActiveCapturePhaseV1,
        explicitConsentRecorded: Bool,
        indicatorVisibleOrAudible: Bool,
        indicatorAccessibilityLabelKey: String?,
        indicatorPersistsAcrossSceneInactivity: Bool
    ) throws {
        self.captureID = captureID
        self.kind = kind
        self.phase = phase
        self.explicitConsentRecorded = explicitConsentRecorded
        self.indicatorVisibleOrAudible = indicatorVisibleOrAudible
        self.indicatorAccessibilityLabelKey = indicatorAccessibilityLabelKey
        self.indicatorPersistsAcrossSceneInactivity = indicatorPersistsAcrossSceneInactivity
        let capturing = phase == .capturingIndicatorVisible
        guard captureID != SettingsValidationV1.zeroUUID,
              explicitConsentRecorded == (phase != .awaitingExplicitConsent),
              !capturing
                || (explicitConsentRecorded && indicatorVisibleOrAudible),
              indicatorVisibleOrAudible == capturing,
              indicatorPersistsAcrossSceneInactivity == capturing,
              capturing == (indicatorAccessibilityLabelKey != nil),
              indicatorAccessibilityLabelKey.map({
                SettingsValidationV1.validToken($0, maximumBytes: 160)
              }) ?? true else {
            throw CapabilityContractFailureV1.invalidCaptureTransition
        }
    }

    private enum CodingKeys: String, CodingKey {
        case captureID
        case kind
        case phase
        case explicitConsentRecorded
        case indicatorVisibleOrAudible
        case indicatorAccessibilityLabelKey
        case indicatorPersistsAcrossSceneInactivity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            captureID: container.decode(UUID.self, forKey: .captureID),
            kind: container.decode(ActiveCaptureKindV1.self, forKey: .kind),
            phase: container.decode(ActiveCapturePhaseV1.self, forKey: .phase),
            explicitConsentRecorded: container.decode(
                Bool.self,
                forKey: .explicitConsentRecorded
            ),
            indicatorVisibleOrAudible: container.decode(
                Bool.self,
                forKey: .indicatorVisibleOrAudible
            ),
            indicatorAccessibilityLabelKey: container.decodeIfPresent(
                String.self,
                forKey: .indicatorAccessibilityLabelKey
            ),
            indicatorPersistsAcrossSceneInactivity: container.decode(
                Bool.self,
                forKey: .indicatorPersistsAcrossSceneInactivity
            )
        )
    }

    func transition(
        to next: ActiveCapturePresentationContractV1
    ) throws -> ActiveCapturePresentationContractV1 {
        let allowed: Bool
        switch (phase, next.phase) {
        case (.awaitingExplicitConsent, .consentedNotCapturing),
             (.consentedNotCapturing, .capturingIndicatorVisible),
             (.consentedNotCapturing, .stopped),
             (.consentedNotCapturing, .interrupted),
             (.capturingIndicatorVisible, .stopped),
             (.capturingIndicatorVisible, .interrupted),
             (.interrupted, .consentedNotCapturing):
            allowed = true
        default:
            allowed = false
        }
        guard captureID == next.captureID,
              kind == next.kind,
              allowed,
              !explicitConsentRecorded || next.explicitConsentRecorded else {
            throw CapabilityContractFailureV1.invalidCaptureTransition
        }
        return next
    }
}

enum ScratchDataConsumerV1: String, CaseIterable, Codable, Sendable {
    case canonicalContentAcceptance = "CANONICAL_CONTENT_ACCEPTANCE"
    case backup = "BACKUP"
    case search = "SEARCH"
    case report = "REPORT"
    case supportExport = "SUPPORT_EXPORT"
    case diagnostics = "DIAGNOSTICS"
}

struct ScratchIsolationPolicyV1: Sendable {
    func mayExpose(
        purpose: CapabilityScratchPurposeV1,
        to consumer: ScratchDataConsumerV1
    ) -> Bool {
        switch purpose {
        case .capture, .importData, .source:
            return consumer == .canonicalContentAcceptance
        case .supportExport:
            return consumer == .supportExport
        case .none:
            return false
        }
    }
}

enum ScratchPublicationDispositionV1: String, CaseIterable, Codable, Sendable {
    case acceptedIntoImmutableContent = "ACCEPTED_INTO_IMMUTABLE_CONTENT"
    case rejected = "REJECTED"
    case cancelled = "CANCELLED"
    case expired = "EXPIRED"
    case failed = "FAILED"
}

struct ScratchPublicationLinkageReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let leaseID: UUID
    let purpose: CapabilityScratchPurposeV1
    let disposition: ScratchPublicationDispositionV1
    let immutableContentReceiptDigest: String?
    let scratchDeleted: Bool

    init(
        operationID: UUID,
        leaseID: UUID,
        purpose: CapabilityScratchPurposeV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?,
        scratchDeleted: Bool
    ) throws {
        self.operationID = operationID
        self.leaseID = leaseID
        self.purpose = purpose
        self.disposition = disposition
        self.immutableContentReceiptDigest = immutableContentReceiptDigest
        self.scratchDeleted = scratchDeleted
        let accepted = disposition == .acceptedIntoImmutableContent
        guard operationID != SettingsValidationV1.zeroUUID,
              leaseID != SettingsValidationV1.zeroUUID,
              purpose != .none,
              (!accepted || purpose != .supportExport),
              scratchDeleted,
              accepted == (immutableContentReceiptDigest != nil),
              immutableContentReceiptDigest.map(CompatibilityCanonicalV1.validSHA256) ?? true else {
            throw CapabilityContractFailureV1.invalidScratchLinkage
        }
    }

    private enum CodingKeys: String, CodingKey {
        case operationID
        case leaseID
        case purpose
        case disposition
        case immutableContentReceiptDigest
        case scratchDeleted
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            operationID: container.decode(UUID.self, forKey: .operationID),
            leaseID: container.decode(UUID.self, forKey: .leaseID),
            purpose: container.decode(CapabilityScratchPurposeV1.self, forKey: .purpose),
            disposition: container.decode(
                ScratchPublicationDispositionV1.self,
                forKey: .disposition
            ),
            immutableContentReceiptDigest: container.decodeIfPresent(
                String.self,
                forKey: .immutableContentReceiptDigest
            ),
            scratchDeleted: container.decode(Bool.self, forKey: .scratchDeleted)
        )
    }
}

enum FeaturePolicyStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case enabled = "ENABLED"
    case preparedDisabled = "PREPARED_DISABLED"
}

struct FeaturePolicyDescriptorV1: Codable, Equatable, Sendable {
    let featureID: String
    let state: FeaturePolicyStateV1
    let requiredPackageIDs: [String]
    let requiredCapabilities: [CapabilityIDV1]
    let minimumPlatformMajorVersion: Int
    let safeFallback: ManualFallbackActionV1
    let consumers: [String]
    let policyEntrySHA256: String?

    init(featureID: String, state: FeaturePolicyStateV1, requiredPackageIDs: [String],
         requiredCapabilities: [CapabilityIDV1], minimumPlatformMajorVersion: Int,
         safeFallback: ManualFallbackActionV1, consumers: [String], policyEntrySHA256: String? = nil) {
        self.featureID = featureID; self.state = state; self.requiredPackageIDs = requiredPackageIDs
        self.requiredCapabilities = requiredCapabilities; self.minimumPlatformMajorVersion = minimumPlatformMajorVersion
        self.safeFallback = safeFallback; self.consumers = consumers; self.policyEntrySHA256 = policyEntrySHA256
    }

    private enum CodingKeys: String, CodingKey {
        case featureID, state, requiredPackageIDs, requiredCapabilities
        case minimumPlatformMajorVersion, safeFallback, consumers, policyEntrySHA256
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID); try container.encode(state, forKey: .state)
        try container.encode(requiredPackageIDs, forKey: .requiredPackageIDs)
        try container.encode(requiredCapabilities, forKey: .requiredCapabilities)
        try container.encode(minimumPlatformMajorVersion, forKey: .minimumPlatformMajorVersion)
        try container.encode(safeFallback, forKey: .safeFallback); try container.encode(consumers, forKey: .consumers)
        try container.encode(policyEntrySHA256, forKey: .policyEntrySHA256)
    }

    func validate() throws {
        guard SettingsValidationV1.validToken(featureID, maximumBytes: 160),
              minimumPlatformMajorVersion >= 18,
              requiredPackageIDs == requiredPackageIDs.sorted(),
              Set(requiredPackageIDs).count == requiredPackageIDs.count,
              requiredPackageIDs.allSatisfy({ SettingsValidationV1.validToken($0, maximumBytes: 160) }),
              requiredCapabilities == requiredCapabilities.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(requiredCapabilities).count == requiredCapabilities.count,
              consumers == consumers.sorted(),
              !consumers.isEmpty,
              Set(consumers).count == consumers.count,
              consumers.allSatisfy({ SettingsValidationV1.validToken($0, maximumBytes: 160) }) else {
            throw CapabilityContractFailureV1.invalidValue
        }
        if featureID == "privateSystemDiscovery" {
            let basis = PrivateSystemDiscoveryFeaturePolicySignatureBasisV1(
                consumers: consumers, featureID: featureID,
                minimumPlatformMajorVersion: minimumPlatformMajorVersion,
                requiredCapabilities: requiredCapabilities, requiredPackageIDs: requiredPackageIDs,
                safeFallback: safeFallback, state: state
            )
            guard let policyEntrySHA256,
                  policyEntrySHA256 == CompatibilityCanonicalV1.sha256(try CompatibilityCanonicalV1.encode(basis)),
                  state == .preparedDisabled, requiredCapabilities.isEmpty,
                  requiredPackageIDs.isEmpty, safeFallback == .noFallback else {
                throw CapabilityContractFailureV1.invalidValue
            }
        } else if policyEntrySHA256 != nil {
            throw CapabilityContractFailureV1.invalidValue
        }
    }
}

private struct PrivateSystemDiscoveryFeaturePolicySignatureBasisV1: Codable {
    let consumers: [String]
    let featureID: String
    let minimumPlatformMajorVersion: Int
    let requiredCapabilities: [CapabilityIDV1]
    let requiredPackageIDs: [String]
    let safeFallback: ManualFallbackActionV1
    let state: FeaturePolicyStateV1
}

struct FeaturePolicyRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let features: [FeaturePolicyDescriptorV1]

    init(schemaVersion: Int = Self.schemaVersion, features: [FeaturePolicyDescriptorV1]) throws {
        self.schemaVersion = schemaVersion
        self.features = features.sorted { $0.featureID < $1.featureID }
        try validate()
    }

    func validate() throws {
        try features.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              !features.isEmpty,
              features == features.sorted(by: { $0.featureID < $1.featureID }),
              Set(features.map(\.featureID)).count == features.count else {
            throw CapabilityContractFailureV1.duplicateFeature
        }
    }
}

struct FeaturePolicyResolutionV1: Codable, Equatable, Sendable {
    let featureID: String
    let policyState: FeaturePolicyStateV1
    let requiredPackageIDs: [String]
    let requiredCapabilities: [CapabilityIDV1]
    let minimumPlatformMajorVersion: Int
    let safeFallback: ManualFallbackActionV1
    let bundleDigest: String
}

enum FallbackPersistenceDispositionV1: String, Codable, Sendable {
    case noCanonicalEffectUntilAcceptance = "NO_CANONICAL_EFFECT_UNTIL_ACCEPTANCE"
    case deviceLocalOnly = "DEVICE_LOCAL_ONLY"
    case workspaceCanonicalAfterAcceptance = "WORKSPACE_CANONICAL_AFTER_ACCEPTANCE"
}

enum FallbackDataDispositionV1: String, Codable, Sendable {
    case priorHistoryPreserved = "PRIOR_HISTORY_PRESERVED"
    case scratchDeletedNoCanonicalEffect = "SCRATCH_DELETED_NO_CANONICAL_EFFECT"
    case acceptedImmutableContent = "ACCEPTED_IMMUTABLE_CONTENT"
}

enum FallbackReentryTriggerV1: String, Codable, Sendable {
    case capabilityStateChanged = "CAPABILITY_STATE_CHANGED"
    case permissionChanged = "PERMISSION_CHANGED"
    case userInitiatedRetry = "USER_INITIATED_RETRY"
    case manualPathSelected = "MANUAL_PATH_SELECTED"
}

struct TypedAvailabilityAndFallbackReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let candidateHead: String
    let candidateTree: String
    let providerID: String
    let providerSliceDigest: String
    let consumerID: String
    let capabilityID: CapabilityIDV1
    let availabilityReason: FeatureAvailabilityReasonV1
    let mandatoryCoreComplete: Bool
    let visibleFallback: ManualFallbackActionV1
    let persistenceDisposition: FallbackPersistenceDispositionV1
    let dataDisposition: FallbackDataDispositionV1
    let reentryTrigger: FallbackReentryTriggerV1
    let localizedVisibleStateKey: String
    let localizedVisibleCopyKey: String
    let localizedNextActionKey: String
    let fallbackTestArtifactIDs: [String]
    let evidenceArtifactIDs: [String]
    let zeroUnsupportedPublicClaim: Bool

    init(
        schemaVersion: Int = Self.schemaVersion,
        candidateHead: String,
        candidateTree: String,
        providerID: String,
        providerSliceDigest: String,
        consumerID: String,
        capabilityID: CapabilityIDV1,
        availabilityReason: FeatureAvailabilityReasonV1,
        mandatoryCoreComplete: Bool,
        visibleFallback: ManualFallbackActionV1,
        persistenceDisposition: FallbackPersistenceDispositionV1,
        dataDisposition: FallbackDataDispositionV1,
        reentryTrigger: FallbackReentryTriggerV1,
        localizedVisibleStateKey: String,
        localizedVisibleCopyKey: String,
        localizedNextActionKey: String,
        fallbackTestArtifactIDs: [String],
        evidenceArtifactIDs: [String],
        zeroUnsupportedPublicClaim: Bool
    ) throws {
        self.schemaVersion = schemaVersion
        self.candidateHead = candidateHead
        self.candidateTree = candidateTree
        self.providerID = providerID
        self.providerSliceDigest = providerSliceDigest
        self.consumerID = consumerID
        self.capabilityID = capabilityID
        self.availabilityReason = availabilityReason
        self.mandatoryCoreComplete = mandatoryCoreComplete
        self.visibleFallback = visibleFallback
        self.persistenceDisposition = persistenceDisposition
        self.dataDisposition = dataDisposition
        self.reentryTrigger = reentryTrigger
        self.localizedVisibleStateKey = localizedVisibleStateKey
        self.localizedVisibleCopyKey = localizedVisibleCopyKey
        self.localizedNextActionKey = localizedNextActionKey
        self.fallbackTestArtifactIDs = fallbackTestArtifactIDs
        self.evidenceArtifactIDs = evidenceArtifactIDs
        self.zeroUnsupportedPublicClaim = zeroUnsupportedPublicClaim
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case candidateHead
        case candidateTree
        case providerID
        case providerSliceDigest
        case consumerID
        case capabilityID
        case availabilityReason
        case mandatoryCoreComplete
        case visibleFallback
        case persistenceDisposition
        case dataDisposition
        case reentryTrigger
        case localizedVisibleStateKey
        case localizedVisibleCopyKey
        case localizedNextActionKey
        case fallbackTestArtifactIDs
        case evidenceArtifactIDs
        case zeroUnsupportedPublicClaim
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            candidateHead: container.decode(String.self, forKey: .candidateHead),
            candidateTree: container.decode(String.self, forKey: .candidateTree),
            providerID: container.decode(String.self, forKey: .providerID),
            providerSliceDigest: container.decode(String.self, forKey: .providerSliceDigest),
            consumerID: container.decode(String.self, forKey: .consumerID),
            capabilityID: container.decode(CapabilityIDV1.self, forKey: .capabilityID),
            availabilityReason: container.decode(
                FeatureAvailabilityReasonV1.self,
                forKey: .availabilityReason
            ),
            mandatoryCoreComplete: container.decode(Bool.self, forKey: .mandatoryCoreComplete),
            visibleFallback: container.decode(
                ManualFallbackActionV1.self,
                forKey: .visibleFallback
            ),
            persistenceDisposition: container.decode(
                FallbackPersistenceDispositionV1.self,
                forKey: .persistenceDisposition
            ),
            dataDisposition: container.decode(
                FallbackDataDispositionV1.self,
                forKey: .dataDisposition
            ),
            reentryTrigger: container.decode(
                FallbackReentryTriggerV1.self,
                forKey: .reentryTrigger
            ),
            localizedVisibleStateKey: container.decode(
                String.self,
                forKey: .localizedVisibleStateKey
            ),
            localizedVisibleCopyKey: container.decode(
                String.self,
                forKey: .localizedVisibleCopyKey
            ),
            localizedNextActionKey: container.decode(
                String.self,
                forKey: .localizedNextActionKey
            ),
            fallbackTestArtifactIDs: container.decode(
                [String].self,
                forKey: .fallbackTestArtifactIDs
            ),
            evidenceArtifactIDs: container.decode([String].self, forKey: .evidenceArtifactIDs),
            zeroUnsupportedPublicClaim: container.decode(
                Bool.self,
                forKey: .zeroUnsupportedPublicClaim
            )
        )
    }

    func validate() throws {
        let expectedFallback: ManualFallbackActionV1
        if availabilityReason == .available {
            expectedFallback = .noFallback
        } else {
            expectedFallback = try CapabilityPermissionMatrixV1.current()
                .descriptor(for: capabilityID).manualFallback
        }
        guard schemaVersion == Self.schemaVersion,
              CompatibilityCanonicalV1.validGitObjectID(candidateHead),
              CompatibilityCanonicalV1.validGitObjectID(candidateTree),
              SettingsValidationV1.validToken(providerID, maximumBytes: 160),
              CompatibilityCanonicalV1.validSHA256(providerSliceDigest),
              SettingsValidationV1.validToken(consumerID, maximumBytes: 160),
              SettingsValidationV1.validToken(localizedVisibleStateKey, maximumBytes: 160),
              SettingsValidationV1.validToken(localizedVisibleCopyKey, maximumBytes: 160),
              SettingsValidationV1.validToken(localizedNextActionKey, maximumBytes: 160),
              Self.validArtifactIDs(fallbackTestArtifactIDs),
              Self.validArtifactIDs(evidenceArtifactIDs),
              mandatoryCoreComplete,
              zeroUnsupportedPublicClaim,
              visibleFallback == expectedFallback else {
            throw CapabilityContractFailureV1.invalidValue
        }
    }

    private static func validArtifactIDs(_ values: [String]) -> Bool {
        !values.isEmpty
            && values.count <= 128
            && values == values.sorted()
            && Set(values).count == values.count
            && values.allSatisfy { SettingsValidationV1.validToken($0, maximumBytes: 200) }
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Capability_CapabilityAvailabilityContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Capability_CapabilityAvailabilityContractsV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Capability_CapabilityAvailabilityContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift", role: .lifecycle)
}

enum C31LightingCapabilityBoundaryV1 {
    static let capabilityAvailabilityIsNotLightingEvidence = true
    static let unsupportedMeasurementPathsRemainVisibleAsUnknown = true
    static let capabilityDoesNotClaimInstalledOrOperationalStatus = true
}

// MARK: - C32 assistance capability policy binding

/// Binds each C32 proposal provider to the already released feature-policy
/// vocabulary. The binding carries no runtime provider: OCR, speech, and
/// one-shot location remain prepared-disabled until their own consumer cards.
struct AssistanceFeaturePolicyBindingV1: Equatable, Sendable {
    let assistanceCapabilityID: String
    let featureID: String?
    let requiredCapabilities: [CapabilityIDV1]
    let confidenceRequirement: AssistanceMetadataRequirementV1
    let qualityRequirement: AssistanceMetadataRequirementV1

    static func binding(
        for capability: AssistanceCapabilityReferenceV1
    ) throws -> Self {
        try capability.validate()
        switch capability.capabilityID {
        case "OCR_FIELD_PROPOSAL":
            return .init(
                assistanceCapabilityID: capability.capabilityID,
                featureID: "scanOCR",
                requiredCapabilities: [.scanOCR],
                confidenceRequirement: .required,
                qualityRequirement: .optional
            )
        case "DICTATION_FIELD_PROPOSAL":
            return .init(
                assistanceCapabilityID: capability.capabilityID,
                featureID: "speechDictation",
                requiredCapabilities: [.microphone, .speechDictation],
                confidenceRequirement: .optional,
                qualityRequirement: .optional
            )
        case "ONE_SHOT_LOCATION_PROPOSAL":
            return .init(
                assistanceCapabilityID: capability.capabilityID,
                featureID: "locationCapture",
                requiredCapabilities: [.location],
                confidenceRequirement: .optional,
                qualityRequirement: .optional
            )
        case "DETERMINISTIC_HELPER_PROPOSAL":
            // Closed helpers have no OS/runtime capability. No bundle entry
            // exists yet, so the released loader must resolve them disabled.
            return .init(
                assistanceCapabilityID: capability.capabilityID,
                featureID: nil,
                requiredCapabilities: [],
                confidenceRequirement: .notApplicable,
                qualityRequirement: .notApplicable
            )
        default:
            throw AssistanceContractFailureV1.incompatibleCapability
        }
    }

    func makePolicy(
        capability: AssistanceCapabilityReferenceV1,
        resolution: FeaturePolicyResolutionV1?
    ) throws -> AssistanceCapabilityPolicyV1 {
        guard assistanceCapabilityID == capability.capabilityID else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        let enabled: Bool
        if let featureID {
            guard let resolution,
                  resolution.featureID == featureID,
                  resolution.requiredCapabilities == requiredCapabilities,
                  resolution.safeFallback == .typeManually else {
                throw AssistanceContractFailureV1.incompatibleCapability
            }
            enabled = resolution.policyState == .enabled
        } else {
            guard resolution == nil, requiredCapabilities.isEmpty else {
                throw AssistanceContractFailureV1.incompatibleCapability
            }
            enabled = false
        }
        return try AssistanceCapabilityPolicyV1(
            capability: capability,
            enabled: enabled,
            confidenceRequirement: confidenceRequirement,
            qualityRequirement: qualityRequirement,
            manualFallback: .typeManually
        )
    }
}

enum C33TemporalEvidenceBoundary_Domain_Capability_CapabilityAvailabilityContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

enum AssetLabelCapabilityBoundaryV1 {
    static let cameraInputOnlyResolvesOpaquePayload = true
    static let manualShortCodeHasFeatureParity = true
    static let generationRequiresExplicitStart = true
    static let labelAuthorizationIsProvided = false
    static let printerOrHostedResolverCapabilityIsProvided = false
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Capability_CapabilityAvailabilityContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C34RouteAdoptionBoundary_CapabilityAvailabilityContractsV1 {
    static let availabilityDecisionType = FeatureAvailabilityDecisionV1.self
    static let fallbackReasonType = RouteFallbackReasonV1.self
    static let preservesEssentialOperations = true
    static let startsAutomaticWork = false
}
enum C52ServiceRequestBoundary_CapabilityAvailabilityContractsV1 {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}

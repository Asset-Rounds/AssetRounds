import Foundation

enum AppAccessContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidTransition
    case staleAttempt
    case accessDenied
    case configurationUnknown
    case ingressLimitExceeded
    case ingressNotFound
    case ingressAlreadyTerminal
    case notificationReconciliationRequired
    case effectMismatch
}

enum PrivateSystemDiscoveryAccessBoundaryV1 {
    static let gatePrecedesAvailability = true
    static let gatePrecedesParameterResolution = true
    static let gatePrecedesPreviewAndSpeech = true
    static let lockedResponseContainsPrivateData = false
    static let lockedRequestMayBeReplayed = false
}

struct DeviceLocalAppLockSettingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let key = "device.appLock.enabled"
    static let disabled = DeviceLocalAppLockSettingV1(isEnabled: false)

    let schemaVersion: Int
    let isEnabled: Bool

    init(isEnabled: Bool) {
        schemaVersion = Self.schemaVersion
        self.isEnabled = isEnabled
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, isEnabled }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        let enabled = try values.decode(Bool.self, forKey: .isEnabled)
        guard version == Self.schemaVersion else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        self.init(isEnabled: enabled)
    }
}

enum AppLockReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case coldLaunch = "COLD_LAUNCH"
    case returnedFromBackground = "RETURNED_FROM_BACKGROUND"
    case lockNow = "MANUAL_LOCK"
    case authenticationCancelled = "AUTHENTICATION_CANCELLED"
    case authenticationFailed = "AUTHENTICATION_FAILED"
    case authenticationLockedOut = "AUTHENTICATION_LOCKED_OUT"
    case devicePasscodeRemoved = "PASSCODE_REMOVED"
    case biometryNotEnrolled = "BIOMETRY_NOT_ENROLLED"
    case biometryChanged = "BIOMETRY_CHANGED"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case pendingRecovery = "PENDING_RECOVERY"
    case interrupted = "INTERRUPTED"
}

enum AppAccessStateV1: Equatable, Sendable {
    case disabled
    case locked(reason: AppLockReasonV1)
    case authenticating(attemptID: UUID)
    case unlockedForeground(sessionID: UUID)
    case interruptedLocked
    case configurationUnknownLocked

    var permitsContentAccess: Bool {
        switch self {
        case .disabled, .unlockedForeground: return true
        case .locked, .authenticating, .interruptedLocked,
             .configurationUnknownLocked: return false
        }
    }
}

/// Closed list of C16 content-reading boundaries. A permit is intentionally
/// ephemeral and cannot be persisted, replayed, or used as an identity token.
enum AppAccessContentReadSurfaceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case startupRecovery = "STARTUP_RECOVERY"
    case sceneRestoration = "SCENE_RESTORATION"
    case routeResolution = "ROUTE_RESOLUTION"
    case privateSystemDiscovery = "PRIVATE_SYSTEM_DISCOVERY"
    case search = "SEARCH"
    case searchRebuild = "SEARCH_REBUILD"
    case backupImport = "BACKUP_IMPORT"
    case diagnosticExport = "DIAGNOSTIC_EXPORT"
    case bulkImport = "BULK_IMPORT"
    case render = "RENDER"
    case ocrProposal = "OCR_PROPOSAL"
    case dictationProposal = "DICTATION_PROPOSAL"
    case oneShotLocationProposal = "ONE_SHOT_LOCATION_PROPOSAL"
}

/// OCR must obtain the same ephemeral content permit as every other protected
/// read surface. The permit deliberately carries neither OCR text nor a
/// content identifier, so access telemetry cannot become an OCR side channel.
enum OCRProposalAppAccessBoundaryV1 {
    static let proposalRequiresContentPermit = true
    static let accessLogContainsRecognizedText = false
    static let accessLogContainsSourceBytes = false

    static func validate(_ permit: AppAccessContentPermitV1) throws {
        guard proposalRequiresContentPermit,
              !accessLogContainsRecognizedText,
              !accessLogContainsSourceBytes,
              permit.surface == .ocrProposal,
              permit.state.permitsContentAccess else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }
}

/// C24 keeps dictation and one-shot location as independent protected-read
/// surfaces. These permits contain no transcript, audio, coordinate, or source
/// identity, so denying one capability cannot become a side channel for the
/// other.
enum DictationLocationProposalAppAccessBoundaryV1 {
    static let dictationAndLocationPermissionsAreIndependent = true
    static let accessLogContainsTranscript = false
    static let accessLogContainsAudioBytes = false
    static let accessLogContainsCoordinates = false

    static func validateDictation(_ permit: AppAccessContentPermitV1) throws {
        guard dictationAndLocationPermissionsAreIndependent,
              !accessLogContainsTranscript,
              !accessLogContainsAudioBytes,
              !accessLogContainsCoordinates,
              permit.surface == .dictationProposal,
              permit.state.permitsContentAccess else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    static func validateOneShotLocation(_ permit: AppAccessContentPermitV1) throws {
        guard dictationAndLocationPermissionsAreIndependent,
              !accessLogContainsTranscript,
              !accessLogContainsAudioBytes,
              !accessLogContainsCoordinates,
              permit.surface == .oneShotLocationProposal,
              permit.state.permitsContentAccess else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }
}

enum AppAccessContentReadFailureV1: Error, Equatable, Sendable {
    case denied(surface: AppAccessContentReadSurfaceV1, state: AppAccessStateV1)
}

struct AppAccessContentPermitV1: Equatable, Sendable {
    let surface: AppAccessContentReadSurfaceV1
    let state: AppAccessStateV1

    init(surface: AppAccessContentReadSurfaceV1, state: AppAccessStateV1) throws {
        guard state.permitsContentAccess else {
            throw AppAccessContentReadFailureV1.denied(surface: surface, state: state)
        }
        self.surface = surface
        self.state = state
    }

    /// Test-double compatibility only. Production must provide the stateful,
    /// actor-atomic protocol requirement above.
    static func legacyAuthorized(surface: AppAccessContentReadSurfaceV1) -> Self {
        Self(uncheckedSurface: surface, state: .disabled)
    }

    private init(uncheckedSurface: AppAccessContentReadSurfaceV1, state: AppAccessStateV1) {
        surface = uncheckedSurface
        self.state = state
    }
}

/// No C16 shipping/UI adoption is claimed. S10.6 owns the callers that must
/// replace legacy overloads; until then an acceptance check fails closed.
enum WorkspaceExperienceAppAccessAdoptionBoundaryV1 {
    static let s10ReservedProductionUICallersStillUseLegacyOverloads = true
    static let productionCallerAdoptionComplete = false
    static let postS10_6ReconciliationRequired = true

    static func requireAcceptanceReady() throws {
        guard productionCallerAdoptionComplete,
              !s10ReservedProductionUICallersStillUseLegacyOverloads,
              !postS10_6ReconciliationRequired else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }
}

enum LocalAuthenticationBiometryV1: String, CaseIterable, Codable, Sendable {
    case none = "NONE"
    case faceID = "FACE_ID"
    case touchID = "TOUCH_ID"
    case unavailableUnknown = "UNAVAILABLE_UNKNOWN"
}

enum LocalAuthenticationAvailabilityStatusV1: String, CaseIterable, Codable, Sendable {
    case available = "AVAILABLE"
    case devicePasscodeNotSet = "DEVICE_PASSCODE_NOT_SET"
    case biometryNotEnrolled = "BIOMETRY_NOT_ENROLLED"
    case biometryLockedOut = "BIOMETRY_LOCKED_OUT"
    case unsupported = "UNSUPPORTED"
    case temporarilyUnavailable = "TEMPORARILY_UNAVAILABLE"
}

struct LocalAuthenticationAvailabilityV1: Codable, Equatable, Sendable {
    let status: LocalAuthenticationAvailabilityStatusV1
    let biometry: LocalAuthenticationBiometryV1
    let permitsDeviceOwnerAuthentication: Bool

    init(
        status: LocalAuthenticationAvailabilityStatusV1,
        biometry: LocalAuthenticationBiometryV1,
        permitsDeviceOwnerAuthentication: Bool
    ) throws {
        self.status = status
        self.biometry = biometry
        self.permitsDeviceOwnerAuthentication = permitsDeviceOwnerAuthentication
        guard permitsDeviceOwnerAuthentication == (status == .available) else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    static func systemValue(
        status: LocalAuthenticationAvailabilityStatusV1,
        biometry: LocalAuthenticationBiometryV1
    ) -> Self {
        Self(
            systemStatus: status,
            biometry: biometry,
            permitsDeviceOwnerAuthentication: status == .available
        )
    }

    private init(
        systemStatus: LocalAuthenticationAvailabilityStatusV1,
        biometry: LocalAuthenticationBiometryV1,
        permitsDeviceOwnerAuthentication: Bool
    ) {
        status = systemStatus
        self.biometry = biometry
        self.permitsDeviceOwnerAuthentication = permitsDeviceOwnerAuthentication
    }

    private enum CodingKeys: String, CodingKey {
        case status, biometry, permitsDeviceOwnerAuthentication
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            status: values.decode(
                LocalAuthenticationAvailabilityStatusV1.self,
                forKey: .status
            ),
            biometry: values.decode(LocalAuthenticationBiometryV1.self, forKey: .biometry),
            permitsDeviceOwnerAuthentication: values.decode(
                Bool.self,
                forKey: .permitsDeviceOwnerAuthentication
            )
        )
    }
}

enum LocalAuthenticationTriggerV1: String, CaseIterable, Codable, Sendable {
    case unlock = "UNLOCK"
    case enableAppLock = "ENABLE_APP_LOCK"
    case disableAppLock = "DISABLE_APP_LOCK"
    case repairConfiguration = "REPAIR_CONFIGURATION"
}

enum LocalAuthenticationContextLifecycleV1: String, CaseIterable, Codable, Sendable {
    case freshContextPerAttempt = "FRESH_CONTEXT_PER_ATTEMPT"
}

struct LocalAuthenticationAttemptV1: Codable, Equatable, Sendable {
    static let policy = "DEVICE_OWNER_AUTHENTICATION"
    let attemptID: UUID
    let trigger: LocalAuthenticationTriggerV1
    let policy: String
    let contextLifecycle: LocalAuthenticationContextLifecycleV1
    let requestedAt: Date
    let localizedReason: String

    init(
        attemptID: UUID,
        trigger: LocalAuthenticationTriggerV1,
        contextLifecycle: LocalAuthenticationContextLifecycleV1 = .freshContextPerAttempt,
        requestedAt: Date,
        localizedReason: String = AppLockCopyV1.authenticationReason
    ) throws {
        self.attemptID = attemptID
        self.trigger = trigger
        policy = Self.policy
        self.contextLifecycle = contextLifecycle
        self.requestedAt = requestedAt
        self.localizedReason = localizedReason
        guard attemptID != SettingsValidationV1.zeroUUID,
              requestedAt.timeIntervalSinceReferenceDate.isFinite,
              policy == Self.policy,
              contextLifecycle == .freshContextPerAttempt,
              localizedReason == AppLockCopyV1.authenticationReason else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    func validate() throws {
        guard attemptID != SettingsValidationV1.zeroUUID,
              requestedAt.timeIntervalSinceReferenceDate.isFinite,
              policy == Self.policy,
              contextLifecycle == .freshContextPerAttempt,
              localizedReason == AppLockCopyV1.authenticationReason else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case attemptID, trigger, policy, contextLifecycle, requestedAt, localizedReason
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPolicy = try values.decode(String.self, forKey: .policy)
        guard decodedPolicy == Self.policy else {
            throw AppAccessContractFailureV1.invalidValue
        }
        try self.init(
            attemptID: values.decode(UUID.self, forKey: .attemptID),
            trigger: values.decode(LocalAuthenticationTriggerV1.self, forKey: .trigger),
            contextLifecycle: values.decode(
                LocalAuthenticationContextLifecycleV1.self,
                forKey: .contextLifecycle
            ),
            requestedAt: values.decode(Date.self, forKey: .requestedAt),
            localizedReason: values.decode(String.self, forKey: .localizedReason)
        )
    }
}

enum LocalAuthenticationOutcomeV1: String, CaseIterable, Codable, Sendable {
    case authenticated = "AUTHENTICATED"
    case userCancelled = "USER_CANCELLED"
    case appCancelled = "APP_CANCELLED"
    case systemCancelled = "SYSTEM_CANCELLED"
    case authenticationFailed = "AUTHENTICATION_FAILED"
    case biometryLockedOut = "BIOMETRY_LOCKED_OUT"
    case biometryNotEnrolled = "BIOMETRY_NOT_ENROLLED"
    case biometryChanged = "BIOMETRY_CHANGED"
    case devicePasscodeNotSet = "DEVICE_PASSCODE_NOT_SET"
    case unavailable = "UNAVAILABLE"
    case interrupted = "INTERRUPTED"
}

enum LockedIngressKindV1: String, CaseIterable, Codable, Sendable {
    case appIntent = "APP_INTENT"
    case backupFile = "BACKUP_FILE"
    case csvFile = "CSV_FILE"
    case document = "DOCUMENT"
    case export = "EXPORT"
    case protectedIngress = "PROTECTED_INGRESS"
    case reminderNotification = "REMINDER_NOTIFICATION"
    case restoration = "RESTORATION"
    case reviewFile = "REVIEW_FILE"
    case rootRoute = "ROOT_ROUTE"
    case scan = "SCAN"
    case share = "SHARE"
    case shareFile = "SHARE_FILE"
    case shortcut = "SHORTCUT"
    case spotlight = "SPOTLIGHT"
    case supportRecovery = "SUPPORT_RECOVERY"
    case thirdPartyAdapterFile = "THIRD_PARTY_ADAPTER_FILE"
}

enum LockedIngressDispositionV1: String, CaseIterable, Codable, Sendable {
    case stagedProtectedPendingAuthentication = "STAGED_PROTECTED_PENDING_AUTHENTICATION"
    case duplicateAdopted = "DUPLICATE_ADOPTED"
    case rejectedUnsupportedKind = "REJECTED_UNSUPPORTED_KIND"
    case rejectedSize = "REJECTED_SIZE"
    case rejectedStorage = "REJECTED_STORAGE"
    case rejectedProtectedData = "REJECTED_PROTECTED_DATA"
    case deferredAmbiguousOwnership = "DEFERRED_AMBIGUOUS_OWNERSHIP"
    case readyForAuthenticatedValidation = "READY_FOR_AUTHENTICATED_VALIDATION"
    case expiredDeleted = "EXPIRED_DELETED"
    case consumed = "CONSUMED"
    case erased = "ERASED"
}

struct PendingLockedExternalIntentV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumByteCount: UInt64 = 4_294_967_296
    static let maximumLifetimeSeconds: TimeInterval = 14_400

    let schemaVersion: Int
    let intentID: UUID
    let operationID: UUID
    let kind: LockedIngressKindV1
    let opaqueStagingID: String
    let byteCount: UInt64
    let sha256: String
    let receivedAt: Date
    let expiresAt: Date
    let disposition: LockedIngressDispositionV1

    init(
        intentID: UUID,
        operationID: UUID,
        kind: LockedIngressKindV1,
        opaqueStagingID: String,
        byteCount: UInt64,
        sha256: String,
        receivedAt: Date,
        expiresAt: Date,
        disposition: LockedIngressDispositionV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.intentID = intentID
        self.operationID = operationID
        self.kind = kind
        self.opaqueStagingID = opaqueStagingID
        self.byteCount = byteCount
        self.sha256 = sha256
        self.receivedAt = receivedAt
        self.expiresAt = expiresAt
        self.disposition = disposition
        try validate()
    }

    func validate() throws {
        let expectedOpaquePrefix = "opaque-"
        let opaqueSuffix = String(opaqueStagingID.dropFirst(expectedOpaquePrefix.count))
        guard schemaVersion == Self.schemaVersion,
              intentID != SettingsValidationV1.zeroUUID,
              operationID != SettingsValidationV1.zeroUUID,
              opaqueStagingID.hasPrefix(expectedOpaquePrefix),
              UUID(uuidString: opaqueSuffix)?.uuidString.lowercased() == opaqueSuffix,
              byteCount > 0, byteCount <= Self.maximumByteCount,
              CompatibilityCanonicalV1.validSHA256(sha256),
              receivedAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > receivedAt,
              expiresAt.timeIntervalSince(receivedAt) <= Self.maximumLifetimeSeconds else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    func advancing(to next: LockedIngressDispositionV1) throws
        -> PendingLockedExternalIntentV1 {
        try PendingLockedExternalIntentV1(
            intentID: intentID,
            operationID: operationID,
            kind: kind,
            opaqueStagingID: opaqueStagingID,
            byteCount: byteCount,
            sha256: sha256,
            receivedAt: receivedAt,
            expiresAt: expiresAt,
            disposition: next
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, intentID, operationID, kind, opaqueStagingID
        case byteCount, sha256, receivedAt, expiresAt, disposition
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try self.init(
            intentID: values.decode(UUID.self, forKey: .intentID),
            operationID: values.decode(UUID.self, forKey: .operationID),
            kind: values.decode(LockedIngressKindV1.self, forKey: .kind),
            opaqueStagingID: values.decode(String.self, forKey: .opaqueStagingID),
            byteCount: values.decode(UInt64.self, forKey: .byteCount),
            sha256: values.decode(String.self, forKey: .sha256),
            receivedAt: values.decode(Date.self, forKey: .receivedAt),
            expiresAt: values.decode(Date.self, forKey: .expiresAt),
            disposition: values.decode(LockedIngressDispositionV1.self, forKey: .disposition)
        )
    }
}

enum AppLockRecoveryDispositionV1: String, CaseIterable, Codable, Sendable {
    case noRecoveryRequired = "NO_RECOVERY_REQUIRED"
    case resumedToLocked = "RESUMED_TO_LOCKED"
    case adoptedCompletedEffect = "ADOPTED_COMPLETED_EFFECT"
    case rolledBackPreEffect = "ROLLED_BACK_PRE_EFFECT"
    case expiredIngressRemoved = "EXPIRED_INGRESS_REMOVED"
    case ambiguousStateLocked = "AMBIGUOUS_STATE_LOCKED"
    case erased = "ERASED"
}

enum AppLockNotificationPrivacyDispositionV1: String, CaseIterable, Codable, Sendable {
    case unchangedDisabled = "UNCHANGED_DISABLED"
    case enablingPrepared = "ENABLING_PREPARED"
    case genericProjectionApplied = "GENERIC_PROJECTION_APPLIED"
    case genericProjectionAdopted = "GENERIC_PROJECTION_ADOPTED"
    case disablingPrepared = "DISABLING_PREPARED"
    case priorPolicyRebuilt = "PRIOR_POLICY_REBUILT"
    case interruptedRecoveryRequired = "INTERRUPTED_RECOVERY_REQUIRED"
    case erased = "ERASED"
}

enum AppLockLifecycleEventV1: String, CaseIterable, Codable, Sendable {
    case coldLaunch = "COLD_LAUNCH"
    case sceneInactive = "SCENE_INACTIVE"
    case sceneBackground = "SCENE_BACKGROUND"
    case sceneActive = "SCENE_ACTIVE"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case lockNow = "LOCK_NOW"
    case termination = "TERMINATION"
    case erase = "ERASE"
}

struct AppLockConfigurationReceiptV1: Equatable, Sendable {
    let operationID: UUID
    let enabled: Bool
    let authenticationOutcome: LocalAuthenticationOutcomeV1
    let notificationDisposition: AppLockNotificationPrivacyDispositionV1
    let settingAdoptedExistingEffect: Bool

    init(
        operationID: UUID,
        enabled: Bool,
        authenticationOutcome: LocalAuthenticationOutcomeV1,
        notificationDisposition: AppLockNotificationPrivacyDispositionV1,
        settingAdoptedExistingEffect: Bool
    ) throws {
        self.operationID = operationID
        self.enabled = enabled
        self.authenticationOutcome = authenticationOutcome
        self.notificationDisposition = notificationDisposition
        self.settingAdoptedExistingEffect = settingAdoptedExistingEffect
        guard operationID != SettingsValidationV1.zeroUUID,
              authenticationOutcome == .authenticated,
              enabled == ([.genericProjectionApplied, .genericProjectionAdopted]
                .contains(notificationDisposition)) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }
}

struct AppLockLifecycleReceiptV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let event: AppLockLifecycleEventV1
    let resultingState: String
    let privacyCoverRequired: Bool
    let contentWasRead: Bool

    init(
        operationID: UUID,
        event: AppLockLifecycleEventV1,
        resultingState: String,
        privacyCoverRequired: Bool,
        contentWasRead: Bool
    ) throws {
        self.operationID = operationID
        self.event = event
        self.resultingState = resultingState
        self.privacyCoverRequired = privacyCoverRequired
        self.contentWasRead = contentWasRead
        guard operationID != SettingsValidationV1.zeroUUID,
              SettingsValidationV1.validToken(resultingState, maximumBytes: 120),
              !contentWasRead else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case operationID, event, resultingState, privacyCoverRequired, contentWasRead
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            operationID: values.decode(UUID.self, forKey: .operationID),
            event: values.decode(AppLockLifecycleEventV1.self, forKey: .event),
            resultingState: values.decode(String.self, forKey: .resultingState),
            privacyCoverRequired: values.decode(Bool.self, forKey: .privacyCoverRequired),
            contentWasRead: values.decode(Bool.self, forKey: .contentWasRead)
        )
    }
}

enum AppLockShippingAdoptionV1: String, Codable, Sendable {
    case deferredUntilAcceptedS10_6Composition = "DEFERRED_UNTIL_ACCEPTED_S10_6_COMPOSITION"
}

enum AppLockLifecycleDispositionV1: String, CaseIterable, Codable, Sendable {
    case deviceLocalOnly = "DEVICE_LOCAL_ONLY"
    case injectedAuthority = "INJECTED_AUTHORITY"
    case excluded = "EXCLUDED"
    case idempotentRecovery = "IDEMPOTENT_RECOVERY"
    case eraseRequired = "ERASE_REQUIRED"
    case notApplicable = "NOT_APPLICABLE"
    case denied = "DENIED"
}

struct AppLockLifecycleDeclarationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let writerCommand: AppLockLifecycleDispositionV1
    let canonicalQuery: AppLockLifecycleDispositionV1
    let migration: AppLockLifecycleDispositionV1
    let filesystemBackup: AppLockLifecycleDispositionV1
    let semanticBackup: AppLockLifecycleDispositionV1
    let replaceRestore: AppLockLifecycleDispositionV1
    let clone: AppLockLifecycleDispositionV1
    let fork: AppLockLifecycleDispositionV1
    let importDisposition: AppLockLifecycleDispositionV1
    let export: AppLockLifecycleDispositionV1
    let search: AppLockLifecycleDispositionV1
    let delete: AppLockLifecycleDispositionV1
    let erase: AppLockLifecycleDispositionV1
    let retention: AppLockLifecycleDispositionV1
    let downgrade: AppLockLifecycleDispositionV1
    let forwardFix: AppLockLifecycleDispositionV1
    let interruptionRecovery: AppLockLifecycleDispositionV1
    let idempotentReceipt: AppLockLifecycleDispositionV1
    let shippingAdoption: AppLockShippingAdoptionV1

    init(
        schemaVersion: Int,
        writerCommand: AppLockLifecycleDispositionV1,
        canonicalQuery: AppLockLifecycleDispositionV1,
        migration: AppLockLifecycleDispositionV1,
        filesystemBackup: AppLockLifecycleDispositionV1,
        semanticBackup: AppLockLifecycleDispositionV1,
        replaceRestore: AppLockLifecycleDispositionV1,
        clone: AppLockLifecycleDispositionV1,
        fork: AppLockLifecycleDispositionV1,
        importDisposition: AppLockLifecycleDispositionV1,
        export: AppLockLifecycleDispositionV1,
        search: AppLockLifecycleDispositionV1,
        delete: AppLockLifecycleDispositionV1,
        erase: AppLockLifecycleDispositionV1,
        retention: AppLockLifecycleDispositionV1,
        downgrade: AppLockLifecycleDispositionV1,
        forwardFix: AppLockLifecycleDispositionV1,
        interruptionRecovery: AppLockLifecycleDispositionV1,
        idempotentReceipt: AppLockLifecycleDispositionV1,
        shippingAdoption: AppLockShippingAdoptionV1
    ) {
        self.schemaVersion = schemaVersion
        self.writerCommand = writerCommand
        self.canonicalQuery = canonicalQuery
        self.migration = migration
        self.filesystemBackup = filesystemBackup
        self.semanticBackup = semanticBackup
        self.replaceRestore = replaceRestore
        self.clone = clone
        self.fork = fork
        self.importDisposition = importDisposition
        self.export = export
        self.search = search
        self.delete = delete
        self.erase = erase
        self.retention = retention
        self.downgrade = downgrade
        self.forwardFix = forwardFix
        self.interruptionRecovery = interruptionRecovery
        self.idempotentReceipt = idempotentReceipt
        self.shippingAdoption = shippingAdoption
    }

    static let current = AppLockLifecycleDeclarationV1(
        schemaVersion: schemaVersion,
        writerCommand: .deviceLocalOnly,
        canonicalQuery: .deviceLocalOnly,
        migration: .idempotentRecovery,
        filesystemBackup: .excluded,
        semanticBackup: .excluded,
        replaceRestore: .excluded,
        clone: .excluded,
        fork: .excluded,
        importDisposition: .injectedAuthority,
        export: .denied,
        search: .denied,
        delete: .eraseRequired,
        erase: .eraseRequired,
        retention: .deviceLocalOnly,
        downgrade: .denied,
        forwardFix: .idempotentRecovery,
        interruptionRecovery: .idempotentRecovery,
        idempotentReceipt: .idempotentRecovery,
        shippingAdoption: .deferredUntilAcceptedS10_6Composition
    )

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              writerCommand == .deviceLocalOnly,
              canonicalQuery == .deviceLocalOnly,
              migration == .idempotentRecovery,
              filesystemBackup == .excluded,
              semanticBackup == .excluded,
              replaceRestore == .excluded,
              clone == .excluded,
              fork == .excluded,
              importDisposition == .injectedAuthority,
              export == .denied,
              search == .denied,
              delete == .eraseRequired,
              erase == .eraseRequired,
              retention == .deviceLocalOnly,
              downgrade == .denied,
              forwardFix == .idempotentRecovery,
              interruptionRecovery == .idempotentRecovery,
              idempotentReceipt == .idempotentRecovery,
              shippingAdoption == .deferredUntilAcceptedS10_6Composition else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, writerCommand, canonicalQuery, migration
        case filesystemBackup, semanticBackup, replaceRestore, clone, fork
        case importDisposition, export, search, delete, erase, retention
        case downgrade, forwardFix, interruptionRecovery, idempotentReceipt
        case shippingAdoption
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try values.decode(Int.self, forKey: .schemaVersion),
            writerCommand: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .writerCommand),
            canonicalQuery: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .canonicalQuery),
            migration: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .migration),
            filesystemBackup: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .filesystemBackup),
            semanticBackup: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .semanticBackup),
            replaceRestore: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .replaceRestore),
            clone: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .clone),
            fork: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .fork),
            importDisposition: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .importDisposition),
            export: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .export),
            search: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .search),
            delete: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .delete),
            erase: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .erase),
            retention: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .retention),
            downgrade: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .downgrade),
            forwardFix: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .forwardFix),
            interruptionRecovery: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .interruptionRecovery),
            idempotentReceipt: try values.decode(AppLockLifecycleDispositionV1.self, forKey: .idempotentReceipt),
            shippingAdoption: try values.decode(AppLockShippingAdoptionV1.self, forKey: .shippingAdoption)
        )
        try validate()
    }
}

enum AppLockCopyV1 {
    static let setting = "Require Face ID, Touch ID, or your iPhone passcode whenever AssetRounds launches or returns from the background."
    static let disclosure = "App Lock limits access inside AssetRounds. It does not encrypt exported files, replace iPhone data protection, verify a person’s identity, or protect files after you share them."
    static let locked = "AssetRounds is locked. Authenticate with Face ID, Touch ID, or your iPhone passcode to view local work records."
    static let faceIDPurpose = "Use Face ID to unlock your locally stored inspection and service records."
    static let authenticationReason = "Unlock AssetRounds to view local work records."
    static let genericNotificationTitle = "AssetRounds reminder"
    static let genericNotificationBody = "Open AssetRounds to view details."
}
